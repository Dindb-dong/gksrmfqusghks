# Architecture

## 1. 결정 요약

한글변환은 Swift 6.2 기반의 네이티브 macOS 메뉴 막대 앱입니다. 순수 변환·탐지 코어를 시스템 이벤트·Accessibility 계층과 분리해, 개인정보 보호 규칙과 판정 로직을 결정적으로 테스트합니다.

v1은 기존 ABC와 2-Set Korean 입력 소스를 유지하는 **메뉴 막대 에이전트 방식**을 사용합니다. 커스텀 IME는 조합 제어가 더 강하지만 설치·선택 부담과 시스템 입력 소스 UX 차이가 있어 비목표로 둡니다.

## 2. 모듈 경계

```text
HanKeyApp
 ├─ Onboarding / Settings / MenuBar / Notifications
 └─ HanKeyPlatformMac
     ├─ PermissionController
     ├─ EventTap
     ├─ FocusedTextAdapter
     ├─ TextRewriter
     └─ InputSourceController
         ↓
     HanKeyCore
     ├─ KeyToken / WordBuffer
     ├─ DubeolsikComposer / Decomposer
     ├─ TokenSafetyClassifier
     ├─ BoundarySafetyPolicy / RepeatedInputGuard
     ├─ LanguageScorer
     ├─ CorrectionDecisionEngine
     └─ LearningRules
```

- `HanKeyCore`: Foundation에만 의존하며 AppKit, AX, Core Graphics를 import하지 않습니다.
- `HanKeyPlatformMac`: Core Graphics, ApplicationServices, Carbon/HIToolbox, AppKit을 캡슐화합니다.
- `HanKeyApp`: SwiftUI 화면과 사용자 의도를 플랫폼 서비스에 연결합니다.
- 테스트 fixture는 실제 민감 텍스트가 아닌 합성·공개 코퍼스만 포함합니다.

## 3. 이벤트 파이프라인

1. session event tap이 물리 키다운과 수정 키 변화를 수신합니다.
2. 콜백은 최소한의 정규화된 `KeyToken`만 lock-free 또는 actor 경계 뒤로 전달하고 즉시 반환합니다.
3. `WordBuffer`는 현재 앱, 입력 소스, 단어 시작 시각, 물리 키 토큰을 유지합니다.
4. 구분자에서 `TokenSafetyClassifier`가 강제 제외를 먼저 판정합니다.
5. `DubeolsikComposer` 또는 역변환기가 후보를 만듭니다.
6. `CorrectionDecisionEngine`이 원문과 후보 점수 차이를 계산합니다.
7. 고신뢰 결정이면 `CorrectionCoordinator`가 포커스와 커서를 재검증합니다.
8. 텍스트를 교체하고 성공을 확인한 뒤 `InputSourceController`가 목표 소스를 선택합니다.
9. 결과는 콘텐츠가 없는 상태 이벤트로 UI에 전달되고 버퍼는 폐기됩니다.

## 4. 상태 기계

```text
inactive
  └─ permissionsReady → observing
observing
  ├─ printable → buffering
  ├─ secure/excluded → protected
  └─ permissionLost → inactive
buffering
  ├─ printable → buffering
  ├─ boundary → evaluating → rewriting → observing
  ├─ focus/navigation/timeout → observing
  └─ secure/excluded → protected
protected
  └─ focus/app/secure change → observing
```

모든 상태 전환에서 원문 버퍼의 생존 조건이 명시되어야 하며, `protected` 진입은 동기적으로 버퍼를 0으로 만듭니다.

## 5. 한글 변환

- 물리 키 위치를 US QWERTY ASCII 토큰으로 정규화합니다.
- 영→한은 두벌식 자모 맵과 현대 한글 조합 상태 기계를 사용합니다.
- 한→영은 완성형 음절을 초성·중성·종성으로 분해하고, 겹자모를 원래 두벌식 키 순서로 확장합니다.
- Unicode NFC/NFD 차이를 정규화하고 compatibility jamo 입력을 별도 처리합니다.
- 순수 Swift 구현을 기본으로 하되 Unicode 규격과 libhangul 공개 동작을 테스트 oracle로 사용합니다. 외부 런타임 의존성 도입은 별도 라이선스·배포 검토 PR을 요구합니다.

## 6. 탐지 엔진

### 강제 제외 단계

보안 상태, 앱/필드 제외, 토큰 길이, URL·이메일·식별자·코드 패턴, 혼합 스크립트, 고엔트로피를 확인합니다. 하나라도 해당하면 언어 점수를 계산하지 않고 `no-op`입니다.

### 점수 단계

```text
score(text) = dictionary
            + character n-gram
            + orthographic quality
            + nearby-language prior
            + per-app prior
            + explicit user rule
            - ambiguity penalties
```

자동 교정은 `candidateScore - originalScore >= automaticThreshold`일 때만 허용합니다. 모델과 사전 버전은 앱 버전과 함께 고정해 동일 입력의 결과가 재현 가능해야 합니다.

### 데이터 선택

- 대형 생성 모델이나 네트워크 모델을 사용하지 않습니다.
- v1 사전 증거는 macOS의 로컬 `NSSpellChecker`에서 주입하며, 결과가 없으면 fail-closed합니다. 근거는 `docs/decisions/0001-system-lexicon-evidence.md`에 기록합니다.
- 향후 라이선스가 명확한 단어 빈도·n-gram 데이터를 번들하려면 별도 ADR과 precision 검증을 요구합니다.
- 고유명사와 사용자 용어는 명시적 로컬 예외 목록으로 보완합니다.

## 7. 텍스트 교체

한글 IME는 단어 경계 전까지 marked text를 유지할 수 있으므로 자동 교정은 기본적으로 경계 이벤트 후 다음 run-loop에서 실행합니다.

1. 이벤트 시점의 앱 PID, 포커스 element, selection range를 기록합니다.
2. 실행 직전에 동일 포커스와 예상 caret인지 재확인합니다.
3. `AXSelectedTextRange`로 대상 범위를 지정합니다.
4. sentinel이 붙은 Unicode 합성 이벤트로 replacement를 입력합니다.
5. 실제 caret/selection 변화가 예상과 일치하면 성공으로 간주합니다.
6. 성공 후에만 입력 소스를 변경합니다.

전체 `AXValue` 덮어쓰기와 클립보드 paste는 서식·클립보드 오염 위험 때문에 기본 경로에서 금지합니다. 편집기가 범위를 노출하지 않으면 자동 교정을 보류하고 수동 fallback 가능성만 표시합니다.

교체와 입력 소스 변경은 OS 차원의 원자적 트랜잭션이 아니므로 마지막 한 건의 before/after/source 정보를 메모리에 유지해 전용 Undo를 제공합니다.

## 8. 입력 소스 전환

- 활성화되고 선택 가능한 ABC와 2-Set Korean의 안정적 source ID를 시작 시 해석합니다.
- 표시 이름에 의존하지 않고 Text Input Source Services 속성을 사용합니다.
- `TISSelectInputSource` 결과와 시스템 변경 알림을 확인합니다.
- 다음 printable event와 경쟁하면 coordinator가 짧게 직렬화하되, timeout 시 원래 이벤트를 손실 없이 전달하고 상태 오류를 남깁니다.

## 9. 권한·보안

- 입력 모니터링: 전역 이벤트 관찰
- 손쉬운 사용: 포커스 필드 조회, 선택 범위 설정, 합성 입력
- 로그인 항목: 사용자 opt-in

권한은 별도로 요청·철회될 수 있습니다. Secure Keyboard Entry 또는 `AXSecureTextField`가 확인되면 이벤트 내용을 처리하지 않고 메모리 버퍼를 폐기합니다. 앱은 권한이 넓다는 사실을 온보딩에서 숨기지 않습니다.

## 10. 저장소와 개인정보

저장 허용:

- 설정 토글과 단축키
- bundle ID 기반 앱 제외 목록
- 사용자가 승인한 Always/Never 단어쌍
- 콘텐츠 없는 최근 오류 코드와 버전 정보

메모리에서만 허용:

- 현재 포커스에서 사용자가 같은 물리 키 입력을 반복해 교정을 거부한 의도를 나타내는 최대 32개의 bounded 토큰 시퀀스
- 이 반복 입력 기억은 포커스 변경, 보호 상태, 권한 상실, 관찰 중지 또는 앱 종료 시 폐기

디스크 저장 금지:

- 원시 키 이벤트 또는 키코드 연속열
- 현재·과거 단어 버퍼
- 선택된 텍스트와 주변 문장
- 앱별 입력 내용 통계

런타임 코드의 `URLSession`, Network.framework, 소켓 사용을 CI 정적 검사로 금지합니다. 업데이트 확인이 필요해질 경우에도 입력 helper와 분리된 명시적 사용자 동작으로 별도 설계합니다.

## 11. 동시성과 성능

- event tap callback: 할당·IPC·사전 조회 없이 token enqueue만 수행
- `InputCoordinator` actor: 순서와 상태 소유
- detector: immutable 자산을 사용하며 actor 밖의 bounded task에서 계산 가능
- AX/TIS 작업: 전용 serial executor 또는 main-thread 요구사항 준수
- watchdog: tap timeout 비활성화를 감지해 재활성화하고 사용자에게 반복 실패를 알림

## 12. 실패 정책

- 포커스 변경: 교정 취소
- 선택 범위 불일치: 교정 취소
- 텍스트 교체 실패: 입력 소스 변경 금지
- 입력 소스 전환 실패: 텍스트는 유지하고 상태 오류 + Undo 제공
- 권한 상실: 즉시 중단, 버퍼 폐기, 설정 안내
- Secure Input: 정상 보호 상태로 취급
- 비호환 앱: 자동 교정 보류, 앱 제외 제안

## 13. 배포

- 첫 배포: Developer ID 서명·공증된 universal DMG
- Release build는 Hardened Runtime을 사용합니다.
- 앱 업데이트는 v1 범위에서 수동 다운로드로 시작할 수 있으며, 자동 업데이트 도입 시 별도 위협 모델과 서명 검증이 필요합니다.
- 재현 가능한 빌드·서명·공증 스크립트와 SBOM/의존성 고지를 릴리스 산출물에 포함합니다.
