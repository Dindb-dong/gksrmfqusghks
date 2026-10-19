# Changelog

## 1.0.2 — 2026-10-19

- Switch the effective input source after verified corrections while preserving rapid follow-up input.
- Preserve queued input order during normal corrections, with modifier cleanup on cancellation and timeout.
- Stop before text replacement when the ABC/two-set Korean input sources or Control-Space shortcut cannot be verified.
- Share a single 200ms handoff deadline across replacement verification and input-source switching.

## 1.0.1 — 2026-09-09

- Add local-only aggregate correction statistics with per-word counts and reset controls.
- Preserve every standard symbol boundary and safely handle delayed straight and smart quotes.
- Recognize valid Korean words typed with shifted Dubeolsik keys without weakening code-identifier protection.
- Add the app icon and current settings and menu-bar screenshots to the README.

## 1.0.0 — 2026-08-27

- Local-only ABC↔2-Set Korean physical-key conversion with complete modern Hangul round trips.
- Fail-closed automatic detector for addresses, identifiers, code-like and high-entropy values.
- Bounded global input observation with Secure Input, focus, app, pointer, input-source, sleep, and session invalidation.
- Complete physical special-symbol boundary recognition with URL, query, path, and identifier continuations failing closed.
- Focus-scoped repeated-input intent guard that preserves a user's second identical physical-key entry for the session.
- Verified clipboard-free AX range rewrite and post-success input-source switching.
- Privacy-first onboarding, permission recovery, menu status, accessible Light/Dark settings.
- Manual selection/last-word conversion, strict one-step Undo, optional global shortcuts.
- Persisted automatic-correction opt-in plus independent login launch, correction announcement, and optional sound controls.
- Atomic private local Always/Never learning rules and app exclusions with corruption recovery, export, and reset.
- Protected live surfaces for browser address bars, terminals, IDEs, password managers, remote desktops, secure and unknown fields.
- Universal arm64/x86_64 Developer ID, Hardened Runtime, notarized DMG release pipeline with SBOM and checksums.
