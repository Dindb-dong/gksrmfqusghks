# Security and Privacy

## Security posture

한글변환은 키보드 입력을 관찰하고 다른 앱의 텍스트를 교체할 수 있는 강한 권한을 요구합니다. 따라서 기능 편의보다 데이터 최소화, 실패 시 무동작, 감사 가능한 동작을 우선합니다.

## Threat model

보호 대상:

- 사용자가 입력하는 비밀번호, 인증 코드, 개인·업무 텍스트
- 클립보드와 다른 앱의 문서 내용
- 로컬 학습 예외와 앱 사용 패턴
- 배포 바이너리와 업데이트 신뢰 체인

주요 위협:

- 원시 키 입력의 디스크 기록 또는 네트워크 유출
- 보안 필드 오인식과 짧은 포커스 전환 race
- 합성 이벤트의 재귀 처리 또는 잘못된 앱으로 전달
- URL·명령·코드의 잘못된 자동 변환
- 서명되지 않거나 변조된 업데이트
- 의존성·사전 데이터의 라이선스 또는 공급망 문제

## Mandatory controls

1. 런타임 네트워크 기능과 텔레메트리를 포함하지 않습니다.
2. 원시 이벤트와 현재 단어는 메모리에만 두고 최소 수명과 최대 길이를 적용합니다. 반복 교정 거부 의도는 현재 포커스에 한해 최대 32개 토큰 시퀀스만 유지합니다.
3. Secure Keyboard Entry 또는 secure field를 감지하면 버퍼를 즉시 폐기합니다.
4. 포커스·PID·selection을 교정 직전에 재검증합니다.
5. 자동 교정은 위험 패턴과 앱에서 fail closed 합니다.
6. 합성 이벤트에는 process sentinel을 붙이고 외부 이벤트와 구분합니다.
7. 로그는 상태 코드, 시간, 앱 버전만 허용하며 텍스트·키코드·bundle 내 문서 제목을 금지합니다.
8. 설정 파일은 최소 권한으로 원자적으로 기록하고 손상 시 안전 기본값으로 복구합니다.
9. Release artifact는 Hardened Runtime, Developer ID, notarization, checksum을 사용합니다.
10. 외부 코드·사전·모델은 라이선스, 해시, 업데이트 근거를 PR에 기록합니다.

## Data inventory

| Data | Memory | Disk | Network |
|---|---:|---:|---:|
| Current physical key token buffer | Yes, bounded | Never | Never |
| Repeated-intent physical token sequences | Yes, max 32 in current focus | Never | Never |
| Focused text/current word | Transient when required | Never | Never |
| App exclusion bundle IDs | Yes | Yes | Never |
| Always/Never word pairs | Yes | Yes, user-controlled | Never |
| Permission and feature settings | Yes | Yes | Never |
| Content-free diagnostic codes | Bounded | User opt-in export | Never |

## Secure input invariants

- 보호 상태 진입 즉시 current buffer count는 0입니다.
- 보호 상태에서는 detector와 learning API가 호출되지 않습니다.
- 보호 상태 종료 후 이전 buffer를 복구하지 않습니다.
- 비밀번호 관리자 bundle ID는 사용자 설정으로 자동 교정 허용할 수 없습니다.
- secure field 여부를 확인할 수 없고 컨텍스트가 민감하면 무동작합니다.

## Network prohibition

- 앱 runtime target에서 `URLSession`, `Network`, BSD socket, WebSocket import/use를 정적 검사합니다.
- CI 의존성·사전 다운로드는 버전과 checksum이 고정된 별도 build-time 단계이며 런타임 앱에 downloader를 넣지 않습니다.
- 업데이트 기능은 v1 이후 별도 보안 설계 없이는 추가하지 않습니다.

## Vulnerability reports

공개 이슈에 민감한 재현 텍스트나 로그를 올리지 마십시오. 저장소의 GitHub Security Advisory 비공개 보고 경로를 사용하고, 문제가 발생한 앱 이름·macOS 버전·한글변환 버전·콘텐츠 없는 상태 코드만 공유하십시오.

## Unsupported security claims

- “모든 비밀번호 필드를 완벽하게 식별한다”고 주장하지 않습니다.
- 비 sandboxed Developer ID 앱의 네트워크 불가를 OS가 강제한다고 주장하지 않습니다. 대신 네트워크 코드 부재, 공개 소스, 정적·동적 검증 증거를 제공합니다.
- 접근성 권한이 단순하거나 낮은 위험이라고 축소 설명하지 않습니다.
