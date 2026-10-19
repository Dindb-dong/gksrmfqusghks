#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_PATTERN='NSPasteboard|UIPasteboard|kAXValueAttribute|(^|[^A-Za-z])(print|debugPrint|NSLog|os_log)[[:space:]]*\(|Logger[[:space:]]*\('

scan_sources() {
    if command -v rg >/dev/null 2>&1; then
        rg --line-number --glob '*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"
    else
        grep -R -n -E --include='*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"
    fi
}

if scan_sources; then
    echo "clipboard, whole-field AX access, or runtime logging is forbidden" >&2
    exit 1
fi

# Only these range-scoped writes/capability checks may use AXSelectedText. Reads remain forbidden.
python3 - "$HANKEY_ROOT" <<'PYTHON'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]) / "Sources"
allowed = root / "HanKeyPlatformMac" / "FocusedTextRewriter.swift"
forms = [
    r"AXUIElementIsAttributeSettable\s*\(\s*element,\s*kAXSelectedTextAttribute as CFString,\s*&settable\s*\)",
    r"AXUIElementSetAttributeValue\s*\(\s*element,\s*kAXSelectedTextAttribute as CFString,\s*text as CFString\s*\)",
]
for path in root.rglob("*.swift"):
    source = path.read_text()
    if path == allowed:
        for form in forms:
            source = re.sub(form, "", source, count=1)
    if "kAXSelectedTextAttribute" in source:
        sys.exit(f"Unapproved AXSelectedText access in {path.relative_to(root)}")
PYTHON

echo "No forbidden clipboard, whole-field AX, or runtime logging APIs found."
