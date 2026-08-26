# Dependency Inventory

## Runtime

한글변환은 현재 제3자 런타임 패키지에 의존하지 않습니다.

| Component | Provider | Purpose | Bundled | License handling |
|---|---|---|---:|---|
| Swift Standard Library | Apple | language runtime | platform/toolchain managed | Apple toolchain terms |
| SwiftUI, AppKit | Apple | app and settings UI | system frameworks | not redistributed separately |
| CoreGraphics | Apple | event permission and future event tap | system framework | not redistributed separately |
| ApplicationServices | Apple | Accessibility trust and future AX access | system framework | not redistributed separately |
| Carbon/HIToolbox | Apple | Secure Input and future input-source services | system framework | not redistributed separately |

## Build and CI

| Component | Pin | Purpose | License |
|---|---|---|---|
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7`) | source checkout in GitHub Actions | MIT |

## Policy

- 새 패키지, 사전 또는 모델은 별도 PR에서 필요성, upstream, version/hash, license, bundle size, network behavior를 검토합니다.
- floating branch와 unpinned CI action을 사용하지 않습니다.
- 언어 자산 생성용 build-time 의존성은 runtime과 분리하고 재현 명령과 checksum을 기록합니다.
- `Package.resolved`가 생기면 변경 이유와 함께 커밋하고 CI에서 자동 해석 변경을 금지합니다.
