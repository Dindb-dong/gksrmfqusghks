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
| F01 Native scaffold | `feature/native-scaffold` | `e282f8d`, `c51ca11` | local checks passed | pending | pending |

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

## Structural review

- Verdict: pending

## Runtime cleanup

- Pending final goal completion.

## Residual risks

- Language asset licensing and quality are unresolved until F03.
- Signing and notarization require external Apple credentials at F09.
