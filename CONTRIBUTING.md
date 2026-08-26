# Contributing

## Feature workflow

1. `git fetch origin`
2. 최신 `origin/main`에서 `.worktrees/<feature-slug>` worktree와 `feature/<feature-slug>` 브랜치를 생성
3. 관련 PRD/DESIGN/architecture 계약을 확인
4. 작은 검증 가능한 단위로 구현하고 자주 커밋
5. 가장 작은 테스트부터 전체 관련 검증까지 실행
6. 구조·보안·개인정보 리뷰
7. PR 생성, CI 통과, squash merge
8. merge 상태와 원격 main을 확인
9. 해당 세션이 소유한 worktree, 로컬/원격 feature branch만 정리

기존 root checkout에서 기능 구현을 하지 않습니다. 다른 세션의 worktree나 브랜치는 정리하지 않습니다.

## Commit and PR rules

- 한 커밋은 한 가지 검증 가능한 의도를 가집니다.
- 생성 파일이나 대형 언어 자산은 출처·라이선스·재생성 방법과 함께 커밋합니다.
- PR 본문에는 요구사항, 보안/개인정보 영향, 검증, 호환성 변화, rollback을 포함합니다.
- 모든 PR 본문의 마지막 비어 있지 않은 줄은 `by Max Kim (Dindb-dong)`입니다.

## Required checks

- 관련 core/platform/UI tests
- formatting/lint/type/build checks defined by the repository
- detector changes: adversarial precision gate
- event/AX changes: secure input and focus race checks
- runtime changes: no-network and content-free logging scan

## Safety

- 실제 비밀번호, 토큰, 주소, 대화 내용을 fixture나 issue에 넣지 않습니다.
- 자동 교정 범위를 넓히는 변경은 recall 향상만으로 승인하지 않습니다.
- clipboard fallback, network feature, telemetry, remote model은 별도 threat model과 명시적 제품 결정 없이 추가하지 않습니다.
