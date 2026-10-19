#!/usr/bin/env python3
"""Ensure the range-write exception never permits selected-text reads or logging."""
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="hankey-privacy-") as temporary:
    fixture = pathlib.Path(temporary)
    (fixture / "scripts").mkdir()
    sources = fixture / "Sources" / "HanKeyPlatformMac"
    sources.mkdir(parents=True)
    checker = fixture / "scripts" / "verify-privacy-boundaries.sh"
    shutil.copy2(root / "scripts" / checker.name, checker)
    allowed = sources / "FocusedTextRewriter.swift"
    baseline = (root / "Sources" / "HanKeyPlatformMac" / allowed.name).read_text()
    for addition, expected in [
        ("", 0),
        ("\nlet forbidden = kAXSelectedTextAttribute\n", 1),
        ("\nAXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)\n", 1),
        ("\nlet forbidden = kAXValueAttribute\n", 1),
        ('\nprint("forbidden runtime log")\n', 1),
    ]:
        allowed.write_text(baseline + addition)
        result = subprocess.run([str(checker)], capture_output=True)
        assert result.returncode == expected, "Privacy boundary regression"
    allowed.write_text(baseline)
    (sources / "Other.swift").write_text(
        "AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)"
    )
    assert subprocess.run([str(checker)], capture_output=True).returncode == 1
print("Privacy boundary allowlist and forbidden-access checks passed.")
