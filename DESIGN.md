# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-08-26
- Primary product surfaces: 첫 실행 온보딩, 메뉴 막대 상태 메뉴, 설정, 로컬 학습 목록, 비침해 교정 알림
- Evidence reviewed: `PRD.md`, macOS 시스템 설정과 메뉴 막대 관례, Apple 입력 모니터링·손쉬운 사용 권한 흐름, 유사 macOS 입력 도구의 공개 UX
- Assumption: 사용자는 자동화보다 키 입력에 대한 통제와 신뢰를 먼저 확인합니다.

## Brand

- Personality: 조용하고 정확하며 정직한 시스템 도구
- Trust signals: Local only 명시, 권한별 이유, 저장 데이터 보기·초기화, 작동 중/중지 상태, 오픈소스
- Avoid: AI 마법 표현, 게임형 점수·배지, 과도한 애니메이션, 가짜 보안 문구, 키 입력 내용을 노출하는 디버그 화면

## Product goals

- Goals: 한/영 레이아웃 실수를 흐름 안에서 복구하고 다음 입력 소스까지 맞춥니다.
- Non-goals: 일반 글쓰기 AI, 번역, 맞춤법 교정, 클라우드 동기화
- Success signals: 사용자가 교정 사실과 Undo 방법을 이해하고, 보안·제외 상태를 예측할 수 있습니다.

## Personas and jobs

- Primary personas: 한국어·영어를 오가는 일반 사용자, 개발자와 지식 근로자, 개인정보 보호 민감 사용자
- User jobs: 잘못 입력한 단어 복구, 현재 입력 언어 지속, 위험한 앱에서는 자동화 차단, 저장 데이터 확인
- Key contexts of use: 메신저, 이메일, 브라우저 본문, 문서 작성, 검색; 터미널과 주소창은 보호 문맥

## Information architecture

- Primary navigation: 메뉴 막대 메뉴 → 상태/일시정지/마지막 교정/설정/도움말/종료
- Core routes/screens: Welcome, Privacy promise, Permission setup, Try it, Ready, Settings General, Safety, Learning, Shortcuts, About
- Content hierarchy: 현재 보호 상태 → 사용자 제어 → 권한 설명 → 세부 설정

## Design principles

1. **신뢰가 기능보다 먼저다.** 권한 버튼보다 앞서 관찰 범위와 비저장 범위를 설명합니다.
2. **정상 상태는 조용해야 한다.** 앱은 Dock을 점유하지 않고 성공 알림도 짧고 선택 가능해야 합니다.
3. **실패는 구체적이어야 한다.** ‘작동 안 함’ 대신 권한, Secure Input, 제외 앱, 비호환 편집기를 구분합니다.
4. **돌이킬 수 있어야 한다.** 교정 알림과 메뉴에서 즉시 Undo에 접근합니다.
- Tradeoffs: 자동 교정 recall을 낮추더라도 오탐과 신뢰 손상을 줄입니다.

## Visual language

- Color: macOS semantic colors만 사용; 정상은 accent, 일시중지는 secondary, 주의는 system orange, 오류는 system red
- Typography: SF Pro 시스템 타입; 본문 최소 13pt, 권한 설명은 읽기 폭을 제한
- Spacing/layout rhythm: 4pt 기본 단위, 12/16/24pt 주요 간격, 설정 패널은 macOS Form 관례
- Shape/radius/elevation: 시스템 컨트롤과 표준 패널; 장식 카드 남용 금지
- Motion: 상태 전환 120–180ms 이내의 opacity/scale만; Reduce Motion에서 제거
- Imagery/iconography: SF Symbols 우선; 메뉴 막대 아이콘은 `한/A` 상태를 단색으로 명확히 표현

## Components

- Existing components to reuse: SwiftUI `Settings`, `Form`, `Toggle`, `Picker`, `Table`, `MenuBarExtra`, 표준 권한 링크 버튼
- New/changed components: PermissionRow, ProtectionStatus, CorrectionToast, ShortcutRecorder, ExceptionList, LocalOnlyDisclosure, CompatibilityBadge
- Variants and states: normal, paused, permission-required, secure-input, excluded, unsupported, error
- Token/component ownership: App target이 화면을 소유하고 Core 모듈은 사용자 표시 타입을 의존하지 않습니다.

## Accessibility

- Target standard: WCAG 2.2 AA 원칙과 macOS VoiceOver 관례
- Keyboard/focus behavior: 온보딩과 설정 전체 키보드 탐색, 단축키 녹화 취소 경로, 메뉴 명령에 단축키 표시
- Contrast/readability: 색상만으로 상태를 전달하지 않고 아이콘·텍스트를 함께 사용
- Screen-reader semantics: 권한 상태와 자동교정 상태를 결합 레이블로 읽고 변경 결과를 live announcement로 전달
- Reduced motion and sensory considerations: Reduce Motion 준수, 효과음 기본 꺼짐, 성공 피드백은 무음에서도 식별 가능

## Responsive behavior

- Supported breakpoints/devices: macOS 창 폭 520–760pt, 다중 디스플레이, 확대 텍스트
- Layout adaptations: 좁은 폭에서는 설정 sidebar를 상단 picker 또는 단일 열로 전환
- Touch/hover differences: hover에만 정보를 숨기지 않으며 포인터와 키보드 상태가 동일

## Interaction states

- Loading: 권한 재확인과 입력 소스 목록 조회에만 짧은 progress 사용
- Empty: 학습 목록이 비었음을 개인정보 이점과 함께 설명
- Error: 실패 원인, 영향, 복구 버튼, 안전한 현재 동작을 함께 표시
- Success: 권한 준비 완료와 샘플 교정 성공을 명시
- Disabled: 왜 비활성인지와 필요한 선행 조건을 인접 설명
- Offline/slow network: 런타임 네트워크 기능이 없으므로 오프라인이 정상 상태

## Content voice

- Tone: 짧고 직접적이며 기술적으로 정직함
- Terminology: ‘입력 소스’, ‘자동 교정’, ‘마지막 교정 되돌리기’, ‘보안 입력’, ‘앱 제외’ 사용
- Microcopy rules: ‘안전합니다’ 같은 절대 표현 대신 실제로 관찰·저장·전송하는 범위를 설명; 권한 거부를 비난하지 않음

## Implementation constraints

- Framework/styling system: SwiftUI + 필요한 AppKit bridge, 외부 UI 프레임워크 없음
- Design-token constraints: 시스템 semantic color/type/spacing 우선, 별도 디자인 시스템 패키지 금지
- Performance constraints: 이벤트 처리 경로는 UI 렌더링과 분리, 상태 알림이 타이핑을 막지 않음
- Compatibility constraints: macOS 14+ 우선; Light/Dark, VoiceOver, Reduce Motion, 다중 모니터 지원
- Test/screenshot expectations: 핵심 상태별 SwiftUI preview, 접근성 식별자, 온보딩·설정 스크린샷 QA, 메뉴 막대 상태 수동 QA

## Open questions

- [ ] 최종 사용자 표시 이름과 앱 아이콘 / owner: product / impact: release metadata
- [ ] macOS 13 지원 비용 검증 / owner: engineering / impact: deployment target
- [ ] 교정 성공 알림 기본값의 사용자 테스트 / owner: product / impact: interruption level
- [ ] 한국어·영어 사전 라이선스와 번들 크기 / owner: engineering / impact: detector recall and distribution
