# ADR 0001 — Use the macOS system lexicon as optional evidence

- Status: Accepted for v1
- Date: 2026-08-26

## Context

Automatic English-to-Korean correction needs positive candidate evidence; layout-valid Hangul alone is insufficient because arbitrary ASCII keys can form legal Hangul syllables. Bundling a broad English and Korean dictionary introduces license, update, provenance, and app-size obligations before detector quality has been measured.

## Decision

- Use explicit-language `NSSpellChecker` queries (`en_US`, `ko_KR`) as local lexicon evidence.
- Pass the two Boolean results into `CorrectionDecisionEngine` through `LexiconEvidence`.
- Keep system APIs out of `HanKeyCore`; `HanKeyPlatformMac` owns the adapter.
- Treat unknown words and unavailable dictionary coverage as no positive evidence, never as permission to auto-correct.
- Permit a Korean-to-English correction without a dictionary match only when the visible Korean token has a high compatibility-jamo ratio and the English candidate passes strict orthographic scoring.
- Keep the small common-English-bigram table authored in this repository as a heuristic, not a vocabulary or source of truth.

## Consequences

- Core decisions and tests remain deterministic because evidence is injected.
- Runtime quality can vary with macOS dictionary availability, but variation reduces recall rather than safety.
- `yonsei ↔ ㅛㅐㅜㄴ댜` can pass through strong script-mismatch evidence; arbitrary ASCII-to-Hangul still requires a known Korean candidate or an explicit local Always rule.
- There is no third-party dictionary license or runtime network path in v1.
- A bundled asset pipeline requires a future ADR and PR with corpus precision evidence, provenance, license, checksum, and size review.

## Rejected alternatives

- Unlicensed word lists: unacceptable provenance and redistribution risk.
- Cloud or downloadable dictionaries: violates the v1 local-only and no-runtime-network contract.
- Layout validity alone: unacceptable false-positive risk.
- `NLLanguageRecognizer` alone: short-token language detection is not sufficient positive word evidence.
