#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

swift format lint \
    --recursive \
    --strict \
    "$HANKEY_ROOT/Package.swift" \
    "$HANKEY_ROOT/Sources" \
    "$HANKEY_ROOT/Tests"

swift test --package-path "$HANKEY_ROOT" --parallel
"$HANKEY_ROOT/scripts/verify-no-network.sh"
"$HANKEY_ROOT/scripts/build-app.sh" release
