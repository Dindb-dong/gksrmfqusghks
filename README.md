# 한글변환 (`gksrmfqusghks`)

한글변환은 잘못 선택된 키보드 입력 소스로 타이핑한 한글과 영어를 로컬에서 감지해, 안전할 때만 단어를 고치고 다음 입력을 위한 macOS 입력 소스까지 전환하는 네이티브 메뉴 막대 앱입니다.

```text
gksrmffh   → 한글로
ㅛㅐㅜㄴ댜 → yonsei
```

## 제품 원칙

- **Local only:** 키 입력, 문맥, 교정 판단은 네트워크로 전송하지 않습니다.
- **Precision first:** 놓치는 교정보다 잘못 고치는 교정을 더 큰 실패로 취급합니다.
- **Secure by default:** 보안 필드, 주소창, 터미널, IDE, 코드형 토큰은 자동 교정하지 않습니다.
- **Reversible:** 모든 자동 교정은 즉시 되돌릴 수 있고, 되돌림은 다음 판단에 반영됩니다.
- **Honest compatibility:** macOS 보안 경계나 앱의 커스텀 텍스트 구현 때문에 동작하지 않는 곳은 명확히 표시합니다.

## 현재 상태

프로덕션 v1 제품 계약과 Swift 네이티브 scaffold가 마련됐습니다. 자동 교정 기능은 아직 구현되지 않았으며, 이후 기능은 Git worktree와 PR로 순차 개발합니다.

## 개발

```sh
swift test
./scripts/check.sh
```

`./scripts/check.sh`는 Swift format lint, 테스트, 런타임 네트워크 API 금지 검사, ad-hoc 서명된 Release 앱 번들 생성을 순서대로 검증합니다. 결과 앱은 `dist/HanKey.app`에 생성됩니다.

## 문서

- [제품 요구사항](PRD.md)
- [제품·UX 디자인 계약](DESIGN.md)
- [기술 아키텍처](ARCHITECTURE.md)
- [단계별 로드맵](ROADMAP.md)
- [보안 및 개인정보 보호](SECURITY.md)
- [테스트 전략](docs/TESTING.md)
- [의존성 목록](docs/DEPENDENCIES.md)
- [호환성 정책](docs/COMPATIBILITY.md)
- [릴리스 계획](docs/RELEASE.md)
- [기여 및 Git 워크플로](CONTRIBUTING.md)

## 예정 기술 스택

- Swift 6.2
- SwiftUI + AppKit
- Core Graphics event taps
- macOS Accessibility API
- Text Input Source Services
- Swift Package Manager 기반의 순수 로직·플랫폼 계층 분리

## 라이선스

[MIT](LICENSE)
