# Goal Team Intake — production-v1

## Source

- Plan: `PRD.md`, `DESIGN.md`, `ARCHITECTURE.md`, `ROADMAP.md`
- Supporting contracts: `SECURITY.md`, `docs/TESTING.md`, `docs/COMPATIBILITY.md`, `docs/RELEASE.md`
- Repo root: `/Users/maxkim/gksrmfqusghks`

## Objective

Deliver a production-quality, local-only macOS menu bar app that detects high-confidence Korean/English wrong-layout typing, replaces the just-finished token, switches the real system input source, protects sensitive and ambiguous contexts, supports reliable Undo and local exceptions, and ships with reproducible release evidence.

## Acceptance criteria

- All F01–F09 milestones in `ROADMAP.md` are merged to `main` through feature worktree PR cycles.
- All release approval criteria in `PRD.md` are satisfied or a credential-only release gate is explicitly evidenced.
- Security invariants in `SECURITY.md` and design states in `DESIGN.md` are implemented and tested.
- Structural review verdict is `clean` and runtime/feature worktrees are cleaned without touching unrelated work.

## Implementation intent to preserve

- Existing ABC and 2-Set Korean input sources remain the user's real sources.
- Default automatic correction happens at word boundaries and is opt-in.
- Automatic behavior is precision-first and prohibited in secure/code/address/high-risk contexts.
- Runtime has no network behavior and typed content never persists.
- Compatibility limitations are visible rather than hidden behind clipboard mutation.

## Local instructions

- Global `/Users/maxkim/AGENTS.md` and repository `AGENTS.md` apply.
- Features use fresh `.worktrees/<slug>` from `origin/main`.
- Each feature completes PR, CI, merge verification, and session-owned branch/worktree cleanup before the next dependent feature.
- PR body ends exactly once with `by Max Kim (Dindb-dong)`.

## Likely touchpoints

- Swift package/core modules and tests
- Native macOS app target, menu bar, onboarding, settings
- CoreGraphics/ApplicationServices/HIToolbox adapters
- detector assets and reproducible generation pipeline
- GitHub Actions, packaging, signing/notarization scripts
- compatibility and release evidence documents

## Verification evidence

- Swift unit/property/integration/UI tests
- adversarial precision and performance benchmarks
- static no-network/content-log scans
- representative macOS app manual compatibility matrix
- release build, code-signing/notarization/install evidence when credentials allow
- per-PR changed files, commands, CI and merge commit records

## Unknowns and assumptions

- User-facing name is ‘한글변환’; executable target may use `HanKey`.
- macOS 14+ is the starting deployment target and may be lowered after scaffold validation.
- Dictionary/n-gram data choice remains blocked on license and quality evaluation; no unreviewed language assets will be bundled.
- Developer ID/notarization credentials may be unavailable until the release milestone.
- The current Codex App thread owns the Goal; no detached tmux or hidden OMX runtime will be launched.

## Scaffold gate

The repository is documentation-only at intake. F01 is the blocking scaffold task and must establish concrete module/app/test surfaces before later implementation features begin.
