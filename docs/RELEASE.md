# Release Plan

## Distribution

첫 공개 릴리스는 GitHub Releases의 Developer ID 서명·Apple 공증 universal DMG를 목표로 합니다. Mac App Store는 Accessibility와 sandbox 제약을 별도 검증한 뒤 결정합니다.

## Artifacts

- `HanKey.app` universal binary
- versioned DMG
- SHA-256 checksums
- SBOM/dependency and dictionary license notice
- release notes and compatibility matrix
- build, signing, notarization evidence

## Pipeline stages

1. clean checkout and locked dependencies
2. core tests, safety precision gate, UI/build checks
3. Release archive for arm64/x86_64 or universal build
4. Hardened Runtime signing
5. package DMG and sign
6. notarize and staple
7. Gatekeeper assessment and signature verification
8. clean-machine install and permission smoke test
9. GitHub release publish after all previous gates

## Credentials boundary

Apple Developer ID certificate, keychain access, notarization profile, GitHub release mutation은 명시적으로 제공된 자격 증명과 권한이 있을 때만 수행합니다. 자격 증명이 없으면 소스·테스트·재현 가능한 unsigned artifact·정확한 남은 명령까지 완료하고 서명 완료로 주장하지 않습니다.

## Reproducible commands

Ad-hoc universal candidate:

```sh
HANKEY_CODESIGN_IDENTITY=- ./packaging/build-release.sh
./packaging/verify-release.sh
```

Developer ID signed and notarized candidate:

```sh
export HANKEY_CODESIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
export HANKEY_NOTARY_PROFILE='keychain-profile-name'
./packaging/build-release.sh
HANKEY_EXPECT_NOTARIZED=1 ./packaging/verify-release.sh
```

`HANKEY_NOTARY_PROFILE` names credentials already stored with `xcrun notarytool store-credentials`; secrets are never passed as command arguments or committed. Publish the GitHub Release only from a clean merged `main` after the notarized verification and installed-app TCC smoke matrix pass.

## Versioning

- Semantic Versioning
- `0.x`: 공개 pre-release
- `1.0.0`: PRD release gate 충족
- detector asset revision은 app version과 함께 기록

## Rollback

- GitHub release assets는 삭제보다 새 수정 버전을 발행합니다.
- 자동 업데이트가 없으므로 사용자가 이전 공증 버전을 명시적으로 설치할 수 있도록 checksum과 release notes를 유지합니다.
- 보안 또는 데이터 처리 회귀는 즉시 자동 교정 기본 중지 안내와 수정 릴리스를 우선합니다.
