# Production v1 Roadmap

각 기능은 최신 `origin/main`에서 생성한 `.worktrees/<slug>` 전용 worktree에서 작업합니다. 기능별로 테스트·구조 리뷰·PR·CI·squash merge를 완료한 뒤 해당 worktree와 로컬/원격 브랜치를 정리합니다.

## 완료 정의 공통 계약

- 요구사항과 `DESIGN.md` 관련 절을 구현합니다.
- 사용자 입력 원문을 로그·fixture·snapshot에 추가하지 않습니다.
- 가장 작은 관련 테스트를 먼저 실행하고 전체 core test, lint/build를 위험도에 맞게 확장합니다.
- PR 설명에 보안·개인정보 영향과 검증 증거를 기록합니다.
- CI 성공과 실제 merge commit을 확인한 뒤에만 정리합니다.

## F00 — Repository bootstrap and contracts

- README, PRD, DESIGN, architecture, security, testing, compatibility, release 문서
- Goal intake와 완료 ledger
- 라이선스와 저장소 운영 계약

검증: Markdown 링크·Git 상태·원격 main 확인

## F01 — Native project scaffold and CI

- Swift package module 경계와 macOS 앱 target
- 기본 MenuBarExtra, Settings, test targets
- formatting/lint policy, GitHub Actions, build-app script
- deterministic dependency lock and license inventory

검증: `swift test`, debug/release build, 최소 앱 bundle smoke test

## F02 — Dubeolsik conversion core

- 물리 key token model
- ABC→2-set 조합과 2-set→ABC 분해
- Shift, 겹모음, 겹받침, 받침 이동, jamo/NFC/NFD
- property-based round-trip과 회귀 fixture

검증: pure core unit suite, sanitizer where supported

## F03 — Safety classifier and detector

- tokenizer와 word boundary
- URL/email/IP/UUID/hash/path/code/high-entropy filters
- 사전·n-gram asset pipeline과 라이선스 검증
- confidence tiers, user rules, adversarial corpus, benchmark

검증: precision gate, deterministic benchmark, Sparkle 외 no-direct-network asset build

## F04 — Permissions, event tap, and secure-input guard

- Input Monitoring/Accessibility 상태와 요청 흐름
- session event tap, sentinel, event normalization, tap recovery
- focus/app/navigation invalidation
- secure field and Secure Keyboard Entry hard stop

검증: platform integration tests, permission-state unit tests, manual secure-field matrix

## F05 — Text rewrite, input source switch, and transaction coordinator

- focused text range adapter
- composition-safe boundary correction
- clipboard-free Unicode replacement
- ABC/2-Set source discovery and selection
- race serialization, rollback/Undo record, incompatibility reporting

검증: TextEdit test harness, Chrome/Electron/manual matrix, example E2E

## F06 — Production onboarding and settings UX

- privacy-first onboarding and local sandbox demo
- permission wizard and recovery states
- menu bar statuses, pause controls, correction feedback
- General/Safety/Shortcuts/About settings
- VoiceOver, keyboard navigation, localization-ready copy

검증: UI tests/previews, accessibility audit, Light/Dark/Reduce Motion screenshots

## F07 — Manual correction, Undo, and local learning

- configurable shortcuts and collision handling
- last-word and selected-text manual conversion
- one-step reliable Undo
- Always/Never/app exclusion editors and reset/export policy

검증: state-machine and persistence tests, app restart, corrupted-settings recovery

## F08 — Compatibility hardening and adversarial QA

- representative native/browser/Electron app matrix
- terminals/IDEs/password managers/URL bars protection
- focus races, rapid typing, key repeat, multi-display, sleep/wake
- latency/idle CPU/memory benchmarks
- content-free diagnostic report

검증: release candidate QA ledger with residual unsupported cases

## F09 — Release engineering and public launch readiness

- universal archive/app/DMG pipeline
- Hardened Runtime, signing, notarization, artifact verification
- privacy policy, support/security templates, changelog
- install/update/uninstall documentation
- clean-machine smoke test

검증: signed artifact when credentials are available; otherwise exact credential gate and reproducible unsigned artifact evidence

## Release gate

F01–F09가 모두 main에 병합되고 `PRD.md` 출시 승인 기준이 충족되며 구조 리뷰가 `clean`일 때만 production v1 Goal을 완료합니다.
