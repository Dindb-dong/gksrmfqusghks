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
| F04 Input observation | `feature/input-observation` | `6e5e73c`, `ad9893f`, `604a43b`, `a6b39df` | 32 local tests and Release build passed | pending | pending |

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
- Permission prompts are explicit user actions. The runtime does not start until the user enables correction and both required permissions exist.
- Manual real-app secure-field validation remains intentionally open for the F08 compatibility matrix because CI and unattended local runs cannot grant or manipulate macOS TCC consent.

## Structural review

- Verdict: pending

## Runtime cleanup

- Pending final goal completion.

## Residual risks

- Real-app TCC, secure-field, and focus-race behavior remains to be exercised in the F08 compatibility matrix.
- Signing and notarization require external Apple credentials at F09.
