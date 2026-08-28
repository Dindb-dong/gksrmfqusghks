#!/bin/bash

set -euo pipefail

HANKEY_APP="${1:?usage: $0 /path/to/HanKey.app [identity]}"
HANKEY_IDENTITY="${2:--}"
HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$HANKEY_APP" && "$HANKEY_APP" == *.app ]] || {
    echo "expected an app bundle: $HANKEY_APP" >&2
    exit 64
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HANKEY_APP/Contents/Info.plist")" == "com.dindbdong.hankey" ]] || {
    echo "refusing unexpected app bundle identifier" >&2
    exit 64
}

sign_args=(--force --options runtime --sign "$HANKEY_IDENTITY")
if [[ "$HANKEY_IDENTITY" == "-" ]]; then
    sign_args+=(--timestamp=none)
else
    sign_args+=(--timestamp)
fi

# Sign explicit nested code from the inside out. Do not use --deep for signing.
while IFS= read -r -d '' executable; do
    if file "$executable" | grep -q 'Mach-O'; then
        codesign "${sign_args[@]}" "$executable"
    fi
done < <(find "$HANKEY_APP/Contents" -type f -perm -111 -print0)

while IFS= read -r nested; do
    codesign "${sign_args[@]}" "$nested"
done < <(find "$HANKEY_APP/Contents" -depth \( -name '*.xpc' -o -name '*.framework' -o -name '*.app' \) -type d)

if [[ "$HANKEY_IDENTITY" == "-" ]]; then
    codesign "${sign_args[@]}" \
        --entitlements "$HANKEY_ROOT/App/HanKey.ad-hoc.entitlements" \
        "$HANKEY_APP"
else
    codesign "${sign_args[@]}" "$HANKEY_APP"
fi
codesign --verify --deep --strict --verbose=2 "$HANKEY_APP"
