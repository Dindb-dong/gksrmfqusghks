# 한글변환 (`gksrmfqusghks`)

한글변환은 한/영 입력 소스를 잘못 선택한 채 입력한 단어를 로컬에서 감지하고, 안전하다고 확신할 때만 복구한 뒤 다음 입력을 위한 macOS 입력 소스까지 전환하는 네이티브 메뉴 막대 앱입니다.

```text
gksrmffh  → 한글로
ㅛㅐㅜㄴ댜 → yonsei
ㅜㅐㅅ     → not
/채ㅡㅔㅁㅊㅅ → /compact
```

## 주요 기능

- ABC ↔ 두벌식 입력 실수의 결정적 양방향 변환
- Space와 자연문장 물음표 경계에서의 고신뢰 자동 교정
- cmux·Terminal·iTerm2용 명시적 터미널 모드와 `/`, `--`, `-` 명령 접두사 보존
- URL, 이메일, 주소창, 경로, 코드 식별자, 보안 입력, 비밀번호 관리자 등의 강제 보호
- 교정 직전 PID·포커스·커서·선택 범위를 다시 확인하는 실패 폐쇄형 텍스트 교체
- 마지막 교정 되돌리기, 선택 영역·마지막 단어 수동 변환, 선택 가능한 전역 단축키
- 사용자가 직접 관리하는 `항상 변환`, `변환 제외`, 앱 제외 목록
- 잘못된 자동 교정을 정확히 삭제하고 같은 입력을 다시 했을 때만 제안하는 로컬 학습
- 50–100 범위의 자동 변환 기준 슬라이더(기본 75, 권장 75–85)
- 로그인 시 실행, 교정 알림·효과음, 설치 앱 검색 기반 제외 설정
- Sparkle 기반 자동 업데이트 확인과 수동 `지금 업데이트 확인`

## 개인정보와 안전 원칙

- 키 입력, 현재 단어, 교정 전후 내용, 선택 텍스트는 네트워크로 전송하거나 디스크에 기록하지 않습니다.
- 텔레메트리, 분석, 광고, 클라우드 추론을 사용하지 않습니다.
- 현재 단어 버퍼는 짧게 메모리에만 존재하며 앱 전환·클릭·유휴·보안 입력에서 즉시 폐기됩니다.
- 업데이트 통신은 공개 GitHub Release의 HTTPS 앱캐스트와 사용자가 승인한 릴리스 다운로드로만 제한됩니다.
- 업데이트는 HanKey 전용 Sparkle EdDSA 서명, Developer ID, Apple 공증을 검증합니다.
- 정확도를 재현할 수 없거나 문맥이 애매하면 바꾸지 않습니다. 정밀도가 재현율보다 우선입니다.

자세한 내용은 [개인정보 처리방침](PRIVACY.md)과 [보안 설계](SECURITY.md)를 참고하세요.

## 설치

요구 사항은 macOS 14 이상과 활성화된 ABC·두벌식 입력 소스입니다.

1. [GitHub Releases](https://github.com/Dindb-dong/gksrmfqusghks/releases)에서 최신 `HanKey-<버전>.dmg`와 `SHA256SUMS.txt`를 받습니다.
2. `shasum -a 256 -c SHA256SUMS.txt`로 다운로드를 검증합니다.
3. DMG를 열고 `HanKey.app`을 Applications로 옮깁니다.
4. 앱을 실행하고 전역 자동 교정을 원할 때만 입력 모니터링과 손쉬운 사용 권한을 허용합니다.

설치 후에는 `설정 → 정보 → 소프트웨어 업데이트`에서 자동 확인을 끄거나 즉시 새 버전을 확인할 수 있습니다. 자세한 절차는 [설치·업데이트·삭제 안내](docs/INSTALL.md)를 참고하세요.

## 사용 팁

- 자동 교정이 너무 적으면 `설정 → 일반 → 자동 변환 기준`을 낮춥니다.
- 오탐을 더 줄이고 싶으면 기준을 높입니다. 안전 필터와 명시적 단어 규칙은 이 값보다 항상 우선합니다.
- 터미널 교정은 `설정 → 안전`에서 별도로 켜야 합니다. 경로·URL·옵션처럼 애매한 입력은 그대로 둡니다.
- 자동 교정 결과를 원치 않으면 즉시 되돌리거나, `변환 제외` 목록에서 직접 단어를 관리할 수 있습니다.

## 개발과 검증

```sh
swift test
./scripts/check.sh
```

`./scripts/check.sh`는 Swift format lint, 단위·통합 테스트, Sparkle 외 직접 네트워크 API·클립보드·전체 필드 AX·콘텐츠 로깅 금지 검사, ad-hoc Hardened Runtime 앱 빌드를 수행합니다.

공개 릴리스 파이프라인은 universal 앱·ZIP·DMG·SBOM·checksum을 만들고 Developer ID 서명과 Apple 공증을 검증합니다. 최종 공증 DMG에서 생성한 `appcast.xml`은 HanKey 전용 Keychain EdDSA 키로 서명합니다.

## 문서

- [제품 요구사항](PRD.md)
- [제품·UX 디자인 계약](DESIGN.md)
- [기술 아키텍처](ARCHITECTURE.md)
- [보안 및 개인정보 보호](SECURITY.md)
- [단계별 로드맵](ROADMAP.md)
- [테스트 전략](docs/TESTING.md)
- [의존성 목록](docs/DEPENDENCIES.md)
- [호환성 정책](docs/COMPATIBILITY.md)
- [릴리스 계획](docs/RELEASE.md)
- [설치·업데이트·삭제](docs/INSTALL.md)
- [지원](SUPPORT.md)
- [기여 및 Git 워크플로](CONTRIBUTING.md)

## 기술 스택

- Swift 6.2, SwiftUI, AppKit
- Core Graphics event taps, macOS Accessibility API, Text Input Source Services
- Sparkle 2.9.6
- Swift Package Manager 기반의 순수 코어·macOS 플랫폼·앱 계층 분리

## 라이선스

한글변환은 [MIT 라이선스](LICENSE)로 배포됩니다. 번들된 Sparkle과 외부 구성 요소의 라이선스는 SBOM과 upstream 고지를 따릅니다.
