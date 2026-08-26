# HanKey 1.0.0

HanKey is a local-only macOS menu bar utility that safely repairs text typed with the wrong ABC or 2-Set Korean input source, then switches the input source for the next word.

Highlights:

- Deterministic `gksrmffh → 한글로` and `ㅛㅐㅜㄴ댜 → yonsei` conversion.
- Precision-first automatic detection with URL, identifier, code, random-value, and protected-app exclusions.
- Secure Input, password field, browser address bar, terminal, IDE, password manager, remote desktop, unknown-field, and user app protection.
- Clipboard-free verified range replacement and post-success input-source switching.
- Manual selection/last-word conversion, strict one-step Undo, optional global shortcuts.
- Explicit local Always/Never pairs and app exclusions with export, reset, and corruption recovery.
- Privacy-first onboarding, accessible settings, and content-free diagnostics.

Requirements: macOS 14+, ABC and 2-Set Korean input sources. Global automatic correction requires user-granted Input Monitoring and Accessibility permissions.

The DMG and nested app are universal (`arm64`, `x86_64`), Developer ID signed, Hardened Runtime enabled, Apple notarized, and stapled. Verify downloads with the attached `SHA256SUMS.txt`.
