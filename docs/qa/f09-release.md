# F09 Release Verification

Date: 2026-08-27  
Version: 1.0.0 (1)  
Bundle ID: `com.dindbdong.hankey`

## Build and artifact gates

- `./scripts/check.sh`: 63 tests, strict format, no-network, no-clipboard/whole-field-AX/logging, ad-hoc Hardened Runtime app — passed.
- `packaging/build-universal-app.sh`: SwiftPM arm64+x86_64 Release, compiled asset catalog, embedded SPDX SBOM — passed.
- `packaging/package-release.sh`: versioned ZIP, signed UDZO DMG, SPDX JSON, SHA-256 manifest — passed.
- `packaging/verify-release.sh`: signature, both architectures, icon/SBOM resources, ZIP integrity, DMG checksum/mount, nested app, SHA-256 — passed.

## Signing and notarization

- Identity: Developer ID Application, Team `7995Q7WAZF`
- Hardened Runtime: code directory runtime flag present
- App notarization submission: `b8fb0f8e-6849-45a4-9993-9d8df19ce8a2` — Accepted
- DMG notarization submission: `402459ad-0a7a-416c-a095-4530523715c0` — Accepted
- App staple validate: passed
- DMG staple validate: passed
- Gatekeeper app assessment: `accepted`, source `Notarized Developer ID`
- Gatekeeper DMG assessment: `accepted`, source `Notarized Developer ID`

## Artifact inventory

| Artifact | Size | SHA-256 |
|---|---:|---|
| `HanKey-1.0.0.zip` | 3.0 MB | `14009b1ddbb5e9548a4535a5f834a4812508ff8b461e4fe0912a3877f62c1eaf` |
| `HanKey-1.0.0.dmg` | 3.1 MB | `04e3525eaa7bca96fad03dc4ee7f6388a433659c927f338b81803767138f41e2` |
| `HanKey-1.0.0.spdx.json` | 883 bytes | `d540a9830ad1200428f7067b1d52ffe7ae30ca8e4351e0e31b0858c87f6c66c3` |

Checksums above describe the branch candidate created before the final PR merge. The release job regenerates and records the publishable merged-main checksums; notarization and Gatekeeper status must remain identical.

## Remaining interactive gate

The installed signed app still requires the user to grant persistent macOS Input Monitoring and Accessibility consent before the live TextEdit/browser/Electron/Secure Input matrix can run. No automation silently changed these security settings. GitHub Release publication occurs only after the merged-main artifact and installed-app gate are confirmed.
