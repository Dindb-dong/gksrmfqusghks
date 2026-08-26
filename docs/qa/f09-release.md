# F09 Release Verification

Date: 2026-08-27

Version: 1.0.0 (1)

Bundle ID: `com.dindbdong.hankey`

## Build and artifact gates

- `./scripts/check.sh`: 68 tests, strict format, no-network, no-clipboard/whole-field-AX/logging, ad-hoc Hardened Runtime app — passed.
- `packaging/build-universal-app.sh`: SwiftPM arm64+x86_64 Release, compiled asset catalog, embedded SPDX SBOM — passed.
- `packaging/package-release.sh`: versioned ZIP, signed UDZO DMG, SPDX JSON, SHA-256 manifest — passed.
- `packaging/verify-release.sh`: signature, both architectures, icon/SBOM resources, ZIP integrity, DMG checksum/mount, nested app, SHA-256 — passed.

## Signing and notarization

This evidence describes the reviewed `fb3f222` branch candidate that passed PR #9 CI on Apple Silicon, Intel, and the universal release smoke job.

- Identity: Developer ID Application, Team `7995Q7WAZF`
- Hardened Runtime: code directory runtime flag present
- App notarization submission: `c33ea25e-e5ae-4cdb-93b6-16ef14af51db` — Accepted
- DMG notarization submission: `2e7c7931-87e0-4bfb-b816-e19116d0d69a` — Accepted
- App staple validate: passed
- DMG staple validate: passed
- Gatekeeper app assessment: `accepted`, source `Notarized Developer ID`
- Gatekeeper DMG assessment: `accepted`, source `Notarized Developer ID`

## Artifact inventory

| Artifact | Size | SHA-256 |
|---|---:|---|
| `HanKey-1.0.0.zip` | 3,158,099 bytes | `cdb531db1145e507f9f0e5ef7cac74d221a6ca5f08ad17d2cec370027f3fc449` |
| `HanKey-1.0.0.dmg` | 3,349,813 bytes | `04c35edd5ac9af7876ff5cc240aa1477e231486157382907c39f526028fa033d` |
| `HanKey-1.0.0.spdx.json` | 883 bytes | `d540a9830ad1200428f7067b1d52ffe7ae30ca8e4351e0e31b0858c87f6c66c3` |

Checksums above describe the branch candidate created before the final PR merge. The release job regenerates and records the publishable merged-main checksums; notarization and Gatekeeper status must remain identical.

## Review-driven release gates

- Automatic-correction opt-in now persists across relaunch and resumes only after onboarding with both permissions ready.
- Login launch uses `SMAppService` with enabled, disabled, approval-required, and unavailable states shown independently.
- Correction announcements and effect sound are independent; sound remains off by default.
- User app exclusions are revalidated after the run-loop delay and immediately before any automatic text read or mutation.
- Local rules use atomic writes, failed persistence rolls back in-memory state, the directory/file modes are 0700/0600, and permission-hardening failure does not quarantine valid JSON as corrupt.
- Structural review retains a performance WATCH for per-event post-callback AX context checks; live TCC latency evidence remains required before production completion.
- The exact candidate was installed at `/Applications/HanKey.app`; Gatekeeper accepted it as `Notarized Developer ID`, its binary SHA-256 matched the release app, and the running process exposed zero network sockets.

## Remaining interactive gate

The installed signed app still requires the user to grant persistent macOS Input Monitoring and Accessibility consent before the live TextEdit/browser/Electron/Secure Input matrix can run. No automation silently changed these security settings. GitHub Release publication occurs only after the merged-main artifact and installed-app gate are confirmed.
