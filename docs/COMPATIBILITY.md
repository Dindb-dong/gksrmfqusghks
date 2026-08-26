# Compatibility Policy

## Support levels

- **Supported:** 자동·수동 교정, 입력 소스 전환, Undo를 반복 검증
- **Best effort:** 표준 접근성 범위를 일부만 제공해 수동 fallback이 필요할 수 있음
- **Protected:** 안전상 자동 교정을 의도적으로 비활성화
- **Unsupported:** 앱 또는 원격 환경이 필요한 이벤트·텍스트 범위를 제공하지 않음

## Initial matrix

| Surface | Intended level | Policy |
|---|---|---|
| Native AppKit/SwiftUI text fields | Supported | primary acceptance surface |
| Safari/Chrome normal page fields | Supported/Best effort | address bar is Protected |
| Electron chat/editor fields | Best effort | app-specific AX behavior verified per release |
| Terminal and shells | Protected | manual mode opt-in only after explicit warning |
| IDE code editors | Protected | comments/strings cannot be safely inferred globally |
| Password managers | Protected, immutable | no auto-correction or learning |
| Secure text fields | Protected, immutable | buffer purge and no processing |
| Games/custom canvas editors | Unsupported | no reliable text range contract |
| Remote desktop/VM guest text | Unsupported in v1 | host cannot prove guest text state |

## Compatibility truthfulness

- 앱 이름만으로 지원을 주장하지 않고 입력 표면별로 기록합니다.
- macOS 또는 앱 업데이트마다 smoke matrix를 갱신합니다.
- 실패 시 클립보드를 몰래 덮어쓰지 않습니다.
- 보호·비호환 상태는 메뉴 막대에서 사용자가 확인할 수 있어야 합니다.
