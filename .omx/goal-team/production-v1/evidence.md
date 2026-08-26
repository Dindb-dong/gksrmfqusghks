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
| F02 Dubeolsik core | `feature/dubeolsik-core` | `43424c4`, `7363b27` | local checks passed | pending | pending |

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

## Structural review

- Verdict: pending

## Runtime cleanup

- Pending final goal completion.

## Residual risks

- Language asset licensing and quality are unresolved until F03.
- Signing and notarization require external Apple credentials at F09.
