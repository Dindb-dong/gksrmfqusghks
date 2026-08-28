# Dependency Inventory

## Runtime

한글변환의 유일한 제3자 런타임 패키지는 서명된 소프트웨어 업데이트를 위한 Sparkle입니다.

| Component | Provider | Purpose | Bundled | License handling |
|---|---|---|---:|---|
| Swift Standard Library | Apple | language runtime | platform/toolchain managed | Apple toolchain terms |
| SwiftUI, AppKit | Apple | app and settings UI | system frameworks | not redistributed separately |
| CoreGraphics | Apple | event permission, session event tap, synthetic Unicode events | system framework | not redistributed separately |
| ApplicationServices | Apple | Accessibility trust, focus/range validation | system framework | not redistributed separately |
| Carbon/HIToolbox | Apple | Secure Input, input-source selection, global shortcuts | system framework | not redistributed separately |
| Sparkle | Sparkle Project | HTTPS appcast, EdDSA 검증, 업데이트 설치 | 2.9.6 framework bundled | MIT 및 번들된 외부 라이선스 고지 포함 |

## Build and CI

| Component | Pin | Purpose | License |
|---|---|---|---|
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7`) | source checkout in GitHub Actions | MIT |
| Sparkle source/artifact | `2.9.6`, revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a` | SwiftPM 해석 및 업데이트 도구 | MIT 및 upstream 외부 라이선스 |

## Policy

- 새 패키지, 사전 또는 모델은 별도 PR에서 필요성, upstream, version/hash, license, bundle size, network behavior를 검토합니다.
- floating branch와 unpinned CI action을 사용하지 않습니다.
- 언어 자산 생성용 build-time 의존성은 runtime과 분리하고 재현 명령과 checksum을 기록합니다.
- `Package.resolved`가 생기면 변경 이유와 함께 커밋하고 CI에서 자동 해석 변경을 금지합니다.
