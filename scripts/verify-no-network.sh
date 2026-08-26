#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_PATTERN='(^|[^A-Za-z])(import[[:space:]]+Network|URLSession|NWConnection|NWListener|WebSocket|CFStreamCreatePairWithSocket|socket\()'

if rg --line-number --glob '*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"; then
    echo "runtime network API usage is forbidden" >&2
    exit 1
fi

echo "No forbidden runtime network APIs found."
