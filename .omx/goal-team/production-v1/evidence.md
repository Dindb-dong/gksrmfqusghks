# Production v1 Completion Ledger

## Goal

- Intake: `.omx/goal-team/production-v1/intake.md`
- Plan: `ROADMAP.md`
- Status: active
- Execution: Codex App native path, no OMX tmux team

## Feature ledger

| Feature | Branch / PR | Commits | Verification | Merge | Cleanup |
|---|---|---|---|---|---|
| F00 Repository bootstrap | `main` | `b9eb885` | docs format and remote checks | published to public `main` | n/a |
| F01 Native scaffold | `feature/native-scaffold`, PR #1 | `a5bf7d9` | local and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F02 Dubeolsik core | `feature/dubeolsik-core`, PR #2 | `77bd9d0` | local and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F03 Safety detector | `feature/safety-detector`, PR #3 | `d082bc8` | local and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F04 Input observation | `feature/input-observation`, PR #4 | `b49532b` | local and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F05 Text rewrite | `feature/text-rewrite`, PR #5 | `d4c3be7` | local and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F06 Production UX | `feature/production-ux`, PR #6 | `43053fb` | local, visual QA, and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F07 Manual, Undo, learning | `feature/manual-undo-learning`, PR #7 | `9a163bd` | local and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F08 Compatibility UltraQA | `feature/compatibility-qa`, PR #8 | `d42318b` | local UltraQA and arm64/Intel CI passed | squash merged | worktree and local/remote branch removed |
| F09 Release engineering | `feature/release-engineering`, PR #9 | `fcee2ae`, `a72c5f0`, `4dd0388`, `1b11de2`, `2fbe933`, `fb3f222` | 68 tests; reviewed universal signed/notarized app and DMG installed and verified | pending | pending |

## F01 verification

- Definition of done: concrete Swift core/platform/app/test surfaces, Release app bundle, pinned two-architecture CI, dependency inventory.
- `./scripts/check.sh`: Swift format lint passed; 2 XCTest cases passed; runtime network API scan passed; arm64 Release app built and ad-hoc signed.
- `plutil -lint dist/HanKey.app/Contents/Info.plist`: passed.
- `codesign --verify --deep --strict --verbose=2 dist/HanKey.app`: valid and satisfies designated requirement.
- Launch smoke: `HanKeyApp` process started from the bundle and exited normally through Apple Events.
- GitHub runner labels were checked against the official `actions/runner-images` inventory on 2026-08-26; CI covers `macos-26` arm64 and `macos-26-intel`.
- Current upstream `actions/checkout@v7` was pinned to commit `3d3c42e5aac5ba805825da76410c181273ba90b1`.
- No third-party runtime dependency or language asset was added.
- Structural scope review: core does not import platform frameworks; macOS APIs are isolated in `HanKeyPlatformMac`; app target owns UI; event observation and text mutation are intentionally absent from scaffold.

## F02 verification

- `swift test --filter DubeolsikConverterTests`: 7 tests passed, including all 11,172 modern precomposed Hangul syllables round-tripped through physical QWERTY keys.
- `./scripts/check.sh`: Swift format lint passed; all 11 repository tests passed; runtime network API scan passed; Release app bundle rebuilt and signed.
- Product examples pass in both directions: `gksrmffh ↔ 한글로`, `yonsei ↔ ㅛㅐㅜㄴ댜`.
- Covered Shift double consonants and shifted vowels, compound medials, simple-final migration, compound-final splitting, standalone compatibility jamo, unsupported scalar preservation, and canonical NFD conjoining jamo.
- Structural scope review: conversion files import no Foundation/AppKit/platform framework; physical key state is an immutable Sendable value; the converter performs deterministic layout conversion only and does not make automatic safety decisions reserved for F03.
- Runtime/privacy impact: no persistence, event observation, logging, network path, dependency, or language asset added.

## F03 verification

- `swift test --filter HanKeyCoreTests`: 19 core tests passed before the final high-entropy fixture; targeted high-entropy regression also passed.
- `./scripts/check.sh`: all 20 repository tests passed; Swift format lint, runtime no-network scan, and Release app build/signing passed.
- Protected surfaces fail closed for secure fields, password managers, browser address bars, terminals, IDEs, and remote desktops.
- Adversarial filters cover URL, email, IP/path, UUID, long hex hash, numeric, snake_case, camelCase, ALL_CAPS, punctuation, mixed script, and letters-only high entropy.
- Product detector cases pass: known Korean evidence corrects `gksrmffh → 한글로`; strong malformed-jamo evidence corrects `ㅛㅐㅜㄴ댜 → yonsei`; known originals and unknown ASCII-to-Hangul candidates remain unchanged.
- Explicit Always rules cannot override protected surfaces; Never rules stop an otherwise eligible correction.
- Plan adaptation: no third-party dictionary/n-gram asset is bundled. ADR 0001 uses local `NSSpellChecker` only as injected positive evidence and fails closed when unavailable; core tests remain deterministic.
- Structural scope review: hard safety precedes rules/scoring, decisions remain value-based and Sendable in core, AppKit spell checking stays in `HanKeyPlatformMac`, and no event/persistence/network behavior is activated.

## F04 verification

- `swift test --filter HanKeyPlatformMacTests`: all 7 permission, key normalization, synthetic-event sentinel, secure-role, and focus-identity tests passed.
- `./scripts/check.sh`: all 32 repository tests passed; Swift format lint, runtime no-network scan, Release build, app bundle assembly, and ad-hoc signing passed.
- The listen-only session event tap normalizes physical ANSI letter keys and word boundaries, ignores marked synthetic events, and purges state after tap recovery, pointer input, navigation, modified commands, app activation, or input-source change.
- The in-memory word buffer is capped at 64 physical tokens, expires after 10 seconds, and is irreversibly purged when observation stops or protection activates.
- Secure Keyboard Entry and `AXSecureTextField` are hard stops. Unknown/non-editable focus fails closed, and a process/AX-element identity change purges cross-field state before the next token is accepted.
- Event-tap callback scope review: no Accessibility lookup, disk access, network access, language scoring, text mutation, or UI work occurs inside the callback; the main-RunLoop handoff does not allocate a per-keystroke Swift task.
- F05 structural re-review found that the original main-actor handoff still executed downstream AX work on the callback stack. Commit `e02e7d5` corrected this by asynchronously enqueueing normalized observations before runtime processing.
- Permission prompts are explicit user actions. The runtime does not start until the user enables correction and both required permissions exist.
- Manual real-app secure-field validation remains intentionally open for the F08 compatibility matrix because CI and unattended local runs cannot grant or manipulate macOS TCC consent.

## F05 verification

- `swift test --filter CorrectionTransactionCoordinatorTests`: all 7 transaction tests passed for focus races, exact text validation, whitespace/punctuation preservation, single-line Return behavior, verified replacement, rollback, and input-source failure records.
- `swift test --filter InputSourceControllerTests`: stable ABC and 2-Set Korean IDs are mapped without localized display names; the same IDs were confirmed against this Mac's installed TIS inventory.
- `./scripts/check.sh`: all 40 repository tests passed; Swift format lint, runtime no-network scan, Release build, app bundle assembly, and ad-hoc signing passed.
- Rewrites query only the expected UTF-16 range through `AXStringForRange`; the implementation never reads or replaces the full field value and never uses the clipboard.
- The coordinator revalidates PID, AX element identity, caret, exact original text, and actual boundary immediately before setting `AXSelectedTextRange` and posting sentinel-marked Unicode events.
- Replacement caret position is verified before input-source selection. A still-adjacent unverified replacement is rolled back; a source-switch failure preserves an in-memory record for F07 Undo.
- Real input arriving before mutation moves the caret and cancels correction without suppressing or losing the user's event. Active event holding/replay is not enabled because it would broaden secure-input interception; rapid-typing behavior remains an explicit F08 compatibility and latency gate.
- Runtime/privacy impact: the last correction record is memory-only, no content is displayed or logged, and no persistence, network, clipboard, or third-party dependency was added.

## F06 verification

- `./scripts/check.sh`: all 40 repository tests passed; Swift format lint, runtime no-network scan, Release build, app bundle assembly, and ad-hoc signing passed.
- The first-run AppDelegate path was launched from the built `HanKey.app`; a real 640×520 onboarding window appeared for an incomplete local onboarding state.
- Light privacy onboarding, missing-permission recovery, and Dark settings at the 560pt minimum width were captured by exact HanKey-owned window IDs and visually reviewed without capturing the rest of the desktop.
- `docs/qa/f06-production-ux.md` records the Light/Dark/Reduce Motion, keyboard, VoiceOver, content, and trust review matrix.
- Onboarding orders Local only disclosure before permission actions, supports skipping without enabling observation, provides an isolated deterministic conversion demo, and starts observation only after an explicit final action with both permissions present.
- Menu and settings distinguish active, paused, permission-required, Secure Input protection, and event-tap failure states with icon plus text. Permission controls include a reason, current state, prompt, System Settings deep link, and refresh path.
- Standard controls preserve keyboard traversal; default action, decorative progress hiding, combined status semantics, stable accessibility identifiers, and optional VoiceOver success announcements are present.
- Release structural review: DEBUG-only screenshot routes and forced Dark appearance are compiled out; no raw text, key sequence, correction pair, confidence score, telemetry, clipboard, network client, or third-party UI dependency was added.

## F07 verification

- `./scripts/check.sh`: all 51 repository tests passed; Swift format lint, runtime no-network scan, Release build, app bundle assembly, and ad-hoc signing passed.
- Manual conversion tests cover bounded last-word lookup, explicit selected Hangul conversion, mixed-script rejection, input-source selection, and strict same-focus/caret/text one-step Undo.
- Undo records remain memory-only. An undone pair is persisted as Never only after a separate explicit menu/settings action; automatic Undo never writes learning data.
- Learning rule tests cover normalization, exact-pair replacement, 64-character bounds, load-time revalidation/deduplication, atomic versioned JSON persistence, explicit export, restart reload, and corrupted-file quarantine with empty-state recovery.
- Automatic detection consults only exact local Always/Never pairs, and hard protected-surface safety still executes before explicit rules.
- Shortcut tests cover stable presets and internal collisions. Runtime Carbon registration reports OS conflicts, restores the prior working configuration, and safely disables corrupt/unregisterable saved shortcuts.
- Menu and settings expose selection/last-word conversion, one-step Undo, optional Never learning, shortcut selection, explicit rule add/delete/reset/export, empty/recovery states, and destructive reset confirmation.
- Privacy review: manual last-word reads at most 64 UTF-16 units before the caret; selection conversion is capped at 256; only user-approved rule pairs reach disk; no clipboard, telemetry, network, or content logging API is present.

## F08 verification

- UltraQA cycle 1 completed with the full matrix in `docs/qa/f08-ultraqa.md`; all applicable normal, hostile, malformed, interruption, stale-state, dirty-worktree, hung-command, flaky, and misleading-output scenarios have evidence and cleanup status.
- A high-severity integration gap was found and fixed: protected-surface classifications existed in core but live automatic requests always used standard text. Runtime now classifies bundle/AX context and blocks automatic and manual mutation in terminal, IDE, password manager, remote desktop, browser address, secure, and unknown surfaces.
- `./scripts/check.sh`: all 60 tests passed; format, no-network, new clipboard/whole-field-AX/logging gate, Release build, app assembly, and ad-hoc signing passed.
- Stress evidence: 100,000 synthetic printable events completed in 0.018 seconds locally with at most 64 retained tokens; 1,000 protect/unprotect/system interruption cycles restored zero prior tokens; the stress suite passed 3/3 reruns.
- Sleep/wake, session active/inactive, and display sleep/wake notifications now purge buffered state. Required permissions are rechecked during runtime protection refresh.
- Misleading SUCCESS with exit 1 was rejected; a 300-second child was yielded then interrupted with exit 130; stale iteration 99 was rejected; all isolated harnesses/logs were removed.
- Content-free support export is schema-limited to app/OS/architecture, permission booleans, operational state, and rule count. Typed content, key codes, selection, and app identity are excluded by test.
- Safety boundary: live TextEdit/browser/Electron/password/Secure Input testing was not run because it requires persistent macOS TCC consent. Automated adapter/surface/focus/transaction tests are the safe substitute; live consent remains a truthful F09 release gate.

## F09 verification

- Version 1.0.0 metadata, a production `한 | A` app icon, compiled asset catalog, privacy policy, support guide, changelog, safe issue templates, install/update/uninstall instructions, release notes, and SPDX SBOM are present.
- `./scripts/check.sh`: all 68 tests passed with strict format, no-network, clipboard/whole-field-AX/logging gates, and an ad-hoc Hardened Runtime Release app.
- Universal SwiftPM Release build contains `x86_64 arm64`; app/ZIP/DMG/SBOM/checksum packaging and exact mounted-DMG nested-app verification passed.
- Developer ID identity Team `7995Q7WAZF` signed the app and DMG with Hardened Runtime and secure timestamp.
- Apple app submission `c33ea25e-e5ae-4cdb-93b6-16ef14af51db` and DMG submission `2e7c7931-87e0-4bfb-b816-e19116d0d69a` for reviewed commit `fb3f222` were Accepted; app and DMG staple validation passed.
- Gatekeeper accepted both artifacts with source `Notarized Developer ID`; ZIP/DMG/SBOM SHA-256 values and sizes are recorded in `docs/qa/f09-release.md`.
- A macOS 26 arm runner universal release-smoke job was added after the arm64/Intel validation matrix.
- The final PRD gap for user app exclusions was closed: exact bundle IDs persist locally and protect both automatic and manual paths before text buffering; built-in protected categories remain immutable.
- Review-driven gaps were closed for persisted automatic-correction opt-in, independent login launch/announcement/sound settings, automatic pre-mutation exclusion revalidation, atomic rollback, private 0700/0600 rule storage, and safe handling of permission-hardening failures.
- The exact reviewed candidate was installed at `/Applications/HanKey.app`; its binary hash matched the release app, Gatekeeper accepted it as `Notarized Developer ID`, and the running process exposed no network sockets.
- Installed idle performance: 11 one-minute samples over 10 minutes all reported 0.0% CPU and sleeping state; cumulative CPU stayed at 0.25 seconds, memory at 23 MB, and threads showed no growth.
- Remaining external gate: install the merged-main signed candidate, grant Input Monitoring and Accessibility in macOS System Settings, and execute the live TextEdit/browser/Electron/Secure Input matrix before GitHub Release publication.

## Structural review

- Verdict: pending

## Runtime cleanup

- Pending final goal completion.

## Residual risks

- Real-app TCC, secure-field, and focus-race behavior remains to be exercised in the F08 compatibility matrix.
- Signing and notarization require external Apple credentials at F09.
