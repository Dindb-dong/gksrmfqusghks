# Repository Instructions

## Product contracts

- `PRD.md`, `DESIGN.md`, `ARCHITECTURE.md`, `SECURITY.md` are implementation contracts.
- Runtime behavior is local-only: no telemetry, analytics, cloud inference, network update check, or typed-content persistence.
- Precision beats recall. Secure, ambiguous, code-like, address-like, or unsupported input must fail closed.
- Never log raw key events, key sequences, focused/selected text, or surrounding context.

## Git lifecycle

- Every feature starts from freshly fetched `origin/main` in `.worktrees/<slug>` on `feature/<slug>`.
- Keep commits small and evidence-backed.
- Finish each feature through PR, CI, squash merge, remote verification, then clean only that feature's worktree and branches.
- Do not implement features in the root checkout.

## Architecture

- Keep deterministic conversion, safety, and decision logic in the platform-independent core.
- Keep CGEvent, AXUIElement, input-source, permission, and AppKit behavior behind macOS adapters.
- Event-tap callbacks must not perform Accessibility IPC, dictionary/model work, disk I/O, or UI work.
- Text replacement must be revalidated against current PID, focus, and selection immediately before mutation.

## Verification

- Run the smallest relevant test first, then broader core/build/QA checks as risk warrants.
- Detector changes require adversarial false-positive coverage.
- Secure-input changes require both success and protected/failure-path verification.
- Do not claim signed, notarized, installed, published, or released without direct evidence for that stage.
