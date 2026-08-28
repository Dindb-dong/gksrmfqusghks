# 설치·업데이트·삭제

## 요구 사항

- macOS 14 이상
- macOS에 활성화된 ABC와 두벌식 입력 소스

## 설치

1. 같은 GitHub Release에서 `HanKey-<버전>.dmg`와 `SHA256SUMS.txt`를 받습니다.
2. 터미널에서 checksum을 확인합니다.

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. DMG를 열고 `HanKey.app`을 Applications로 옮깁니다.
4. Applications에서 한글변환을 실행합니다. 앱은 Developer ID로 서명되고 Apple 공증된 상태여야 하며, 검증에 실패한 아티팩트의 Gatekeeper 경고를 우회하지 마세요.
5. 첫 실행 개인정보 설명을 읽고, 전역 자동 교정을 원하는 경우에만 입력 모니터링과 손쉬운 사용 권한을 허용합니다.
6. 필요하면 일반 설정에서 `로그인 시 한글변환 실행`을 켭니다. macOS의 추가 승인이 필요하면 옆의 로그인 항목 설정 버튼을 사용합니다.

## 업데이트

한글변환은 Sparkle로 공개 GitHub Release의 서명된 앱캐스트를 확인합니다.

- 기본적으로 앱 시작 시 기한이 지난 확인을 한 번 수행하고, 실행 중에는 최대 24시간마다 확인합니다.
- `설정 → 정보 → 소프트웨어 업데이트`에서 자동 확인을 끄거나 `지금 업데이트 확인`을 실행할 수 있습니다.
- 업데이트는 HanKey 전용 EdDSA 서명, Developer ID, Apple 공증을 검증합니다.
- 업데이트 통신에는 키 입력, 교정 내용, 로컬 규칙이 포함되지 않습니다.

수동 업데이트도 가능합니다. 한글변환을 종료한 뒤 새 공증 DMG를 내려받아 checksum을 확인하고 Applications의 앱을 교체하세요. Application Support의 로컬 규칙은 유지됩니다. 서명이나 번들 변경을 macOS가 새 앱으로 판단하면 권한을 다시 요청할 수 있습니다.

## 삭제

1. 메뉴 막대 메뉴에서 한글변환을 종료합니다.
2. 로그인 실행을 켰다면 삭제 전에 일반 설정에서 끕니다.
3. `/Applications/HanKey.app`을 휴지통으로 옮깁니다.
4. 로컬 데이터까지 삭제하려면 다음 명령을 선택적으로 실행합니다.

   ```sh
   rm -rf "$HOME/Library/Application Support/HanKey"
   defaults delete com.dindbdong.hankey
   ```

5. 필요하면 시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링·손쉬운 사용에서 HanKey 항목을 제거합니다.

위 선택 명령은 로컬 규칙과 설정을 영구 삭제합니다. 다시 사용할 가능성이 있다면 먼저 규칙을 내보내세요.
