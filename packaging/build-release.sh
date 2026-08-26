#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$HANKEY_ROOT/scripts/check.sh"
"$HANKEY_ROOT/packaging/build-universal-app.sh"
"$HANKEY_ROOT/packaging/package-release.sh"

if [[ -n "${HANKEY_NOTARY_PROFILE:-}" ]]; then
    "$HANKEY_ROOT/packaging/notarize-release.sh"
fi
