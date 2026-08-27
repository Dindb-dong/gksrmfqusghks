# F09 Release Verification

Date: 2026-08-27

Version: 1.0.0 (1)

Bundle ID: `com.dindbdong.hankey`

## Build and artifact gates

- `./scripts/check.sh`: 87 tests, strict format, no-network, no-clipboard/whole-field-AX/logging, ad-hoc Hardened Runtime app — passed.
- `packaging/build-universal-app.sh`: SwiftPM arm64+x86_64 Release, compiled asset catalog, embedded SPDX SBOM — passed.
- `packaging/package-release.sh`: versioned ZIP, signed UDZO DMG, SPDX JSON, SHA-256 manifest — passed.
- `packaging/verify-release.sh`: signature, both architectures, icon/SBOM resources, ZIP integrity, DMG checksum/mount, nested app, SHA-256 — passed.

## Signing and notarization

This evidence describes the feedback-remediated `22779b0` branch candidate. Local full verification passed; PR #9 reruns CI for every subsequent evidence-only commit before merge.

- Identity: Developer ID Application, Team `7995Q7WAZF`
- Hardened Runtime: code directory runtime flag present
- App notarization submission: `96de5766-beaa-445b-a1e6-278a4ccd70d8` — Accepted
- DMG notarization submission: `f2214e2c-ef89-4a47-ad62-6e235408ad0f` — Accepted
- App staple validate: passed
- DMG staple validate: passed
- Gatekeeper app assessment: `accepted`, source `Notarized Developer ID`
- Gatekeeper DMG assessment: `accepted`, source `Notarized Developer ID`

## Artifact inventory

| Artifact | Size | SHA-256 |
|---|---:|---|
| `HanKey-1.0.0.zip` | 3,191,263 bytes | `409a3e0ddf3d6960f3f7b289d4c6e47396903cf750da9e9e31fb34122f6c3436` |
| `HanKey-1.0.0.dmg` | 3,355,176 bytes | `5f6d588f1bc1a7874d39a81d4beb02afb300f3a3ae6edf34d9ede1d40678f860` |
| `HanKey-1.0.0.spdx.json` | 883 bytes | `d540a9830ad1200428f7067b1d52ffe7ae30ca8e4351e0e31b0858c87f6c66c3` |

Checksums above describe the branch candidate created before the final PR merge. The release job regenerates and records the publishable merged-main checksums; notarization and Gatekeeper status must remain identical.

## Review-driven release gates

- Automatic-correction opt-in now persists across relaunch and resumes only after onboarding with both permissions ready.
- Login launch uses `SMAppService` with enabled, disabled, approval-required, and unavailable states shown independently.
- Correction announcements and effect sound are independent; sound remains off by default.
- User app exclusions are revalidated after the run-loop delay and immediately before any automatic text read or mutation.
- Every physical special-symbol key is recognized as a boundary; `.`, `@`, `/`, `\\`, `_`, `-`, and `?` remain hard no-op continuations for domain, email, path, identifier, and query safety.
- A second identical physical-key word after an automatic correction is preserved and remembered only in bounded volatile memory for the same focus; focus/protection/permission/stop changes clear it.
- Local rules use atomic writes, failed persistence rolls back in-memory state, the directory/file modes are 0700/0600, and permission-hardening failure does not quarantine valid JSON as corrupt.
- Structural review retains a performance WATCH for per-event post-callback AX context checks; live TCC latency evidence remains required before production completion.
- The exact candidate was installed at `/Applications/HanKey.app`; Gatekeeper accepted it as `Notarized Developer ID`, and its binary SHA-256 matched the release app at `52d386f1535f92dd73b19d8681139f092ce1626f3a5ca6914ddef75c8e7763a8`.

## Feedback regression evidence

- A private synthetic AppKit text harness verified `gksrmffh~` becomes `한글로~` in the signed installed app.
- `gksrmffh? ` remains byte-for-byte unchanged; focused transaction tests also prove no replacement or source switch, including explicit proposals.
- Re-entering the same physical key sequence after a correction left the input unchanged and surfaced the content-free menu state `반복 입력 유지`.
- The user's exact `skdltm~` fixture remains unchanged because macOS `ko_KR` spell evidence does not recognize `나이스`; this is candidate-evidence recall, not a symbol-boundary failure. An explicit local Always rule is the supported v1 override.
- cmux exposed an editable terminal text area but reported both selected range and selected text as non-settable, no AX actions, and no safe exact-range mutation contract. The signed app now classifies `com.cmuxterm.app` as Protected and performs no automatic backspace rewrite.

## Installed idle runtime gate

- Candidate: installed reviewed notarized app, PID `85385`, onboarding window open, automatic observation not yet authorized.
- Sampling: `top`, 11 samples at 60-second intervals from 04:27:58 through 04:38:02 KST.
- Result: every sample reported 0.0% CPU and `sleeping`; cumulative CPU time stayed at 0.25 seconds, memory stayed at 23 MB, and thread count settled from 4 to 3 without growth.
- Verdict: pass for the 10-minute no-sustained-polling idle gate. This does not replace the post-TCC typing latency p95/p99 gate.

## Remaining release gate

The signed installed candidate retains both macOS permissions and passes the native AppKit feedback matrix above. The broader browser/Electron latency matrix and merged-main artifact regeneration remain required before GitHub Release publication. Terminal automatic correction is intentionally outside v1 because exact range revalidation is unavailable; a custom input method is the safe future architecture for terminal-wide support.
