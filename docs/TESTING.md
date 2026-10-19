# Testing Strategy

## Test pyramid

### Core unit tests

- 두벌식 composition/decomposition
- Unicode NFC/NFD와 compatibility jamo
- tokenizer, buffer invalidation, confidence decision
- URL/email/IP/UUID/hash/path/code/high-entropy safety filters
- Always/Never/app rules and persistence migration
- 전체 ANSI 특수문자·직선/스마트 따옴표 보존 경계, URL·경로 연속 입력 취소, 자동 교정 통계의 집계·저장·손상 복구

### Property and corpus tests

- 지원 음절·키 시퀀스 round-trip
- 공개·합성 한국어/영어 단어쌍
- 짧은 토큰, 고유명사, 기술 약어, 랜덤값의 적대 코퍼스
- 자동 threshold precision regression gate

fixture에는 실제 사용자의 입력, 채팅, 주소, 토큰, 비밀번호를 넣지 않습니다.

### Platform integration tests

- event normalization and sentinel loop prevention
- permission state transitions
- focused element selection range adapter
- input source discovery and change notification
- rewrite cancellation on PID/focus/caret races
- secure state buffer purge

### UI and accessibility tests

- 온보딩 각 권한 상태
- 설정 키보드 탐색과 VoiceOver identifiers
- 오류·빈 상태·일시중지·Secure Input
- Light/Dark, increased contrast, Reduce Motion

### Manual compatibility matrix

- TextEdit, Notes, Mail
- Safari and Chrome: 일반 input, textarea, contenteditable, 주소창
- Slack 또는 대표 Electron editor
- Terminal/iTerm, Xcode/VS Code, password manager: 자동 교정 차단
- 다중 모니터, sleep/wake, 빠른 앱 전환, 빠른 연속 타이핑

## Release gates

- core tests and adversarial precision gate
- debug and release universal builds
- Sparkle 외 직접 네트워크 API 정적 금지 검사
- content-free log scan
- secure field manual verification
- clean-machine install, permission onboarding, correction, Undo, uninstall

## Performance

- detector microbenchmark: token length buckets and cold/warm asset load
- correction latency: boundary event to rewrite start p50/p95/p99
- idle CPU and wakeups over 10 minutes
- sustained 120 WPM synthetic input with key repeat and app switching
- memory growth across 10,000 token cycles

## Failure evidence

테스트를 실행하지 못했거나 기준선 실패가 있으면 PR과 Goal evidence에 정확히 기록합니다. UI가 보였다는 사실을 core correctness 또는 보안 검증으로 대체하지 않습니다.

## Input handoff regressions

- `swift test --filter 'CorrectionTransactionCoordinatorTests|ManualCorrectionCoordinatorTests|FocusedTextRewriterTests|InputSourceControllerTests|GlobalInputEventTapTests|FocusedElementSecurityInspectorTests'` verifies stale selection/activity, exact text at the expected caret, partial-write non-retry, preparation before gating, synthetic bypass, source-notification/readback failures, IME-side text changes, expired handoffs, and protected attribute-read failures.
- `HANKEY_RUN_INPUT_HANDOFF_INTEGRATION=1 swift test --filter InputHandoffIntegrationTests` exercises the real macOS event path with 16 uniquely numbered unmapped key events. A downstream consuming tap is established before posting. Tests cover normal release, deadline release while the main thread is blocked, and idle forwarding; no characters are typed into other apps. Existing Accessibility permission is required; tests otherwise skip without requesting permission.
- `scripts/check-native-input.sh` creates and removes its own temporary AppKit application containing only synthetic `NSTextView` text. It verifies both correction directions, exact caret placement, and subsequent Korean/English key input addressed only to the fixture PID. It never opens an existing document. It briefly changes focus/input source and restores the original source while the fixture remains frontmost. Existing Accessibility permission and enabled ABC/2-Set Korean sources are required. `HANKEY_SCRATCH_PATH` can point at an existing canonical build cache.

Under the current user constraint, run only background unit/static checks; do not run either opt-in event injection or the foreground native fixture. These checks do not establish every chat app's AX support or IME behavior. Do not run live checks in a user's existing document.
