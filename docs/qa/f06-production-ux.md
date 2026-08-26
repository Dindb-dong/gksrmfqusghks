# F06 Production UX QA

Date: 2026-08-27  
Build: local ad-hoc signed Debug app from `feature/production-ux`

## Visual matrix

| Surface | Appearance | State | Result |
|---|---|---|---|
| First-run onboarding | Light | Privacy promise, 640×520 content | Pass: no clipping; hierarchy and Local only disclosure are readable |
| Permission onboarding | Light | Both permissions missing | Pass: each permission has reason, status, request, settings, and refresh controls |
| Settings General | Dark | Permission-required, 560pt minimum width | Pass: segmented navigation, status, toggles, and permission recovery remain readable |
| Reduced Motion | System environment | Onboarding step transition | Pass by structure: transition falls back to opacity only and uses no continuous animation |

The screenshots were captured by exact HanKey-owned CGWindow IDs, not the full user desktop. They are verification artifacts and are not shipped in the application bundle.

## Accessibility review

- Standard SwiftUI controls preserve keyboard traversal and default/cancel semantics.
- Status combines icon, title, and detail; color is never the only signal.
- Permission rows expose the permission name, reason, state, and both recovery actions.
- Onboarding progress dots are decorative and hidden from VoiceOver; textual step count remains visible.
- Core surfaces have stable accessibility identifiers for later UI automation.
- Successful correction announcements honor the local `VoiceOver 교정 알림` preference.

## Trust and content review

- Permission explanations precede permission requests.
- No screen displays typed content, correction pairs, confidence scores, or debug key sequences.
- Secure Input is described as a normal protection state, not an error.
- Unsupported/protected surfaces and the no-clipboard policy are explicit.
- The onboarding demo uses only its local text field and deterministic core conversion.
