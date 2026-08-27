# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-08-27
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
- Key contexts of use: 메신저, 이메일, 브라우저 본문, 문서 작성, 검색; 터미널은 명시적 전용 모드에서만 지원하고 주소창은 항상 보호

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
- New/changed components: PermissionRow, ProtectionStatus, CorrectionToast, ShortcutRecorder, InstalledApplicationPicker, ExcludedApplicationRow, NeverConvertList, LocalOnlyDisclosure, CompatibilityBadge
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
- Disabled: 왜 비활성인지와 필요한 선행 조건을 인접 설명. 복구 가능한 시스템 상태를 단순히 비활성화하지 않음
- Offline/slow network: 런타임 네트워크 기능이 없으므로 오프라인이 정상 상태

## Content voice

- Tone: 짧고 직접적이며 기술적으로 정직함
- Terminology: ‘입력 소스’, ‘자동 교정’, ‘마지막 교정 되돌리기’, ‘보안 입력’, ‘앱 제외’ 사용
- Microcopy rules: ‘안전합니다’ 같은 절대 표현 대신 실제로 관찰·저장·전송하는 범위를 설명; 권한 거부를 비난하지 않음
- Decision notifications: `수락/거부`처럼 대상을 생략하지 않고 `변환하지 않기/계속 자동 변환`처럼 결과를 버튼에 직접 씁니다.

## Implementation constraints

- Framework/styling system: SwiftUI + 필요한 AppKit bridge, 외부 UI 프레임워크 없음
- Design-token constraints: 시스템 semantic color/type/spacing 우선, 별도 디자인 시스템 패키지 금지
- Performance constraints: 이벤트 처리 경로는 UI 렌더링과 분리, 상태 알림이 타이핑을 막지 않음
- Compatibility constraints: macOS 14+ 우선; Light/Dark, VoiceOver, Reduce Motion, 다중 모니터 지원
- Test/screenshot expectations: 핵심 상태별 SwiftUI preview, 접근성 식별자, 온보딩·설정 스크린샷 QA, 메뉴 막대 상태 수동 QA

## Desktop reliability flows

### 로그인 시 실행

- `SMAppService.mainApp`의 `.notFound`는 영구 미지원이 아니라 등록 복구가 필요한 오류 상태로 표시합니다.
- 토글은 등록 시도를 막지 않으며, 실패하면 재시도와 시스템 로그인 항목 열기 경로를 제공합니다.
- `.requiresApproval`에서는 시스템 설정 승인이 필요함을 토글 바로 옆에 설명합니다.

### 터미널 전용 모드

- 터미널은 일반 편집기와 다른 명시적 opt-in 설정으로 제공합니다. 비밀번호 관리자·원격 데스크톱은 계속 지원하지 않습니다.
- AX 범위 교체가 불가능한 터미널에서는 물리 이벤트 버퍼와 현재 PID·포커스·caret selection·입력 소스·이벤트 세대를 교정 직전에 다시 확인합니다. cmux처럼 selection이 고정 `0:0`인 경우 상대 교정은 허용하지만 좌표 기반 삭제 의도 학습은 시작하지 않습니다.
- Space가 AX caret/text에 늦게 반영되는 웹 편집기는 최대 4회의 짧은 bounded retry를 허용합니다. 터미널은 한 번 기다린 뒤 즉시 연속 조회로 caret을 확인하고, AX caret 자체가 아직 없을 때만 bounded retry합니다. 대기 중 새 키, 포커스·입력 소스·보안 상태 변경이나 Space 한 글자로 설명할 수 없는 caret 이동이 생기면 교정하지 않습니다.
- 자동 교정은 Space 또는 별도로 식별된 자연문장 `?`로 끝난 고신뢰 자연어 토큰만 허용합니다. `?`는 짧은 확인 창 동안 후속 입력이 없을 때만 허용하며, 빠른 query continuation은 취소합니다. Enter, Tab, 그 밖의 터미널 문장부호, 경로·URL·옵션·식별자·고엔트로피 토큰은 실패 폐쇄합니다.
- 예외적으로 토큰 맨 앞의 단일 `/`, `--`, `-`는 명령 의도를 높이는 휘발성 문맥으로 취급합니다. `/채ㅡㅔㅁㅊㅅ → /compact`, `--ㅗ디ㅔ → --help`, `-ㅍ → -v`처럼 깨진 한글과 검증된 소문자 ASCII 후보가 함께 있을 때만 Space에서 접두사를 그대로 둔 채 본문을 교정합니다.
- `/도움말`처럼 정상 조합된 한글, URL·경로, 중첩된 접두사, 알 수 없는 후보는 그대로 둡니다. 명령 문맥도 주소창·보안 필드·제외 앱보다 우선하지 않습니다.
- 설명은 클립보드를 쓰지 않는다는 사실과 일반 편집기보다 보수적으로 동작한다는 한계를 함께 알립니다. caret range가 고정된 터미널은 상대 교정을 지원하지만 삭제 기반 학습은 지원하지 않습니다.

### 제외 앱 선택

- 사용자는 번들 ID를 입력하거나 볼 필요가 없습니다. 설정은 설치 앱을 로컬에서 검색해 이름·아이콘으로 선택하는 시트를 엽니다.
- 검색 결과와 제외 목록은 앱 이름을 기본 레이블로 사용하고, 앱이 제거된 경우에만 이해 가능한 대체 이름과 `설치되지 않음` 상태를 표시합니다.
- 선택기는 키보드 검색과 VoiceOver 이름을 지원하며 HanKey 자체와 이미 제외된 앱은 선택할 수 없습니다.

### 변환 제외 학습

- 단순히 같은 입력을 반복한 것만으로는 사용자 의도를 학습하지 않습니다.
- `자동 교정 성공 → 같은 포커스에서 교정 결과 전체를 Backspace로 삭제 → 같은 물리 입력 재완료`가 연속으로 확인될 때만 `변환하지 않음` 규칙을 저장합니다.
- 포커스 이동, 포인터·탐색·명령 키, 다른 입력, 삭제 수 부족·초과가 끼면 학습 후보를 즉시 폐기합니다.
- 설정의 별도 `변환 제외` 탭에서 자동 학습과 직접 추가 항목을 동일하게 보여주며, 원문과 반대 레이아웃 후보를 함께 표시하고 즉시 삭제할 수 있습니다.
- 자동 학습 직후 실제 단어를 포함하지 않는 로컬 알림을 표시합니다. `변환하지 않기`는 제외를 유지하고 `계속 자동 변환`은 동일 규칙을 `항상 변환`으로 이동합니다.
- `항상 변환` 탭도 원문·후보 쌍의 직접 추가, 목록 확인, 삭제를 같은 구조로 제공합니다.
- 알림 권한이 없거나 응답하지 않아도 규칙은 `변환 제외` 목록에서 직접 검토할 수 있습니다.

## Open questions

- [ ] 최종 사용자 표시 이름과 앱 아이콘 / owner: product / impact: release metadata
- [ ] macOS 13 지원 비용 검증 / owner: engineering / impact: deployment target
- [ ] 교정 성공 알림 기본값의 사용자 테스트 / owner: product / impact: interruption level
- [ ] 한국어·영어 사전 라이선스와 번들 크기 / owner: engineering / impact: detector recall and distribution
