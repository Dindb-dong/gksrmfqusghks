# UltraQA Report

## Goal and success criteria

- Goal: harden the production input pipeline against protected surfaces, hostile input, rapid/repeated events, lifecycle transitions, misleading verification, and accidental content disclosure.
- Stop condition: baseline build and tests pass; every applicable scenario below has dynamic evidence; temporary state is removed; safety-bound scenarios have an explicit safe substitute and residual gate.
- Safety bounds applied: no TCC consent changes, no secret or desktop-wide capture, no production/network writes, no content logging, no destructive repository cleanup, and bounded processes only.

## Scenario matrix

| ID | User/attacker model | Scenario | Command/harness | Expected signal | Actual result | Status | Evidence | Cleanup |
|---|---|---|---|---|---|---|---|---|
| BASE-01 | Normal user | Full suite and Release app | `./scripts/check.sh` | zero exit, all tests, both privacy gates, signed app | 60/60 tests; both gates passed; Release app built and ad-hoc signed | Pass | local check output | tracked build output ignored |
| ADV-01 | User enters text in protected app | Terminal, IDE, password manager, remote desktop | `InputSurfaceInspectorTests` | protected before buffer/mutation | runtime bypass found, then all family fixtures protected | Pass after fix | `baa567f` | intentional tests kept |
| ADV-02 | Browser user | Address chrome vs page editor | browser AX descriptor fixtures | address protected; page input standard | Safari/Chrome fixtures pass | Pass | `testBrowserAddressChromeIsProtectedButPageFieldsRemainStandard` | intentional tests kept |
| ADV-03 | Unknown/secure context | Missing bundle or secure role | surface fixtures | fail closed | `.unsupported` / `.secureTextField` | Pass | `testSecureAndUnknownContextsFailClosed` | intentional tests kept |
| ADV-04 | Rapid typist/key repeat | 100,000 physical tokens | `AdversarialStressTests` | bounded memory, large 120 WPM headroom | 0.018s local; token count never above 64 | Pass | stress test output | intentional test kept |
| ADV-05 | Repeated interruption | 1,000 secure/unprotect/system cycles | stress harness | no prior token restoration | empty after every cycle | Pass | stress test output | intentional test kept |
| ADV-06 | Sleep/session/display change | sleep, wake, lock/session, screen notifications | `ContextInvalidationObserverTests` | buffer invalidation | all notifications emit `systemStateChanged` | Pass | `3c15edb` | intentional test kept |
| ADV-07 | Hostile/prompt-like text | traversal, scripts, RTL, NUL, emoji, instruction strings | hostile corpus test | data only; excluded | every fixture fail-closed | Pass | `testHostileUnicodeAndInstructionLikeTextAreDataNotCommands` | intentional test kept |
| ADV-08 | Corrupt/malformed state | invalid JSON, oversized rules, duplicates | learning tests | quarantine or validation | corrupt file quarantined; invalid entries dropped | Pass | F07 + load revalidation suite | fixtures use unique temp directories and self-clean |
| ADV-09 | Focus race | next real input moves caret | transaction race test | correction cancels; user event remains native | no mutation/source switch | Pass | `testFocusRaceCancelsWithoutReadingOrMutatingText` | no artifacts |
| ADV-10 | Misleading tool output | prints SUCCESS, exits 1 | isolated shell harness | exit code wins | recorded exit 1 despite SUCCESS text | Pass | exec evidence `250904` | harness removed |
| ADV-11 | Hung command | 300-second child | yielded exec session + SIGINT | bounded recovery | yielded at 0.25s; exit 130 after SIGINT | Pass | session `65666` | child terminated |
| ADV-12 | Flaky result | lucky one-off stress pass | stress suite repeated three times | 3 complete green runs | 3/3 logs contained 3 tests, 0 failures | Pass | rerun command | three logs removed |
| ADV-13 | Stale workflow state | iteration 99 unrelated session | isolated stale JSON validation | current iteration check rejects | validator exited 1 / false | Pass | jq evidence `d85969` | stale fixture removed |
| ADV-14 | Dirty worktree | intentional feature edits present | `git status --short` before/after | no hidden/reverted user work | only intentional F08 and UltraQA state files observed | Pass | status evidence | temp files removed; state cleared at completion |
| ADV-15 | Support export | diagnostic report requested | report schema test + static privacy scan | no content/app identity fields | exact nine non-content keys; forbidden APIs absent | Pass | `ContentFreeDiagnosticReportTests` | user-selected export only |
| MAN-01 | Real macOS app user | TextEdit, Safari/Chrome, Electron, secure field with live TCC | built app + OS consent | live correction/protection matrix | not executed: accepting Input Monitoring and Accessibility would change security-sensitive persistent OS consent | Safety-blocked | automated AX adapter, surface, focus, transaction, and visual permission-state substitutes | no consent changed |

## Commands run

- `[0] ./scripts/check.sh` — 60 tests, format, no-network, privacy-boundary scan, Release app.
- `[0] swift test --filter InputSurfaceInspectorTests` — protected-app/browser/unknown runtime classification.
- `[0] swift test --filter ContextInvalidationObserverTests` — sleep/wake/session invalidation.
- `[0] swift test --filter AdversarialStressTests` — 100k key repeat, 1k interruptions, hostile text.
- `[0,0,0] stress suite rerun ×3` — flake check.
- `[1] misleading-success harness` — intentional failure correctly detected.
- `[130] bounded 300-second child` — intentional interrupt recovery.
- `[1] stale-state validation` — intentional mismatch correctly rejected.

## Failures found

- ADV-01: the live AppModel always submitted `.standardText`; F03 protected-surface rules existed but were unreachable in runtime. User impact was potential correction in terminals, IDEs, password managers, remote desktops, or browser chrome. Safety impact was high.
- BASE-01 during cycle: a public initializer referenced a private default architecture resolver. The compiler exited non-zero; no false green was accepted. User impact was build failure only.
- ADV-06: sleep, wake, session lock, and display sleep did not explicitly purge a partial word. User impact was stale cross-lifecycle buffer state.

## Fixes applied

- `InputSurfaceInspector.swift`, `FocusedElementSecurityInspector.swift`, `InputObservationRuntime.swift`, `FocusedTextRewriter.swift`: classify and enforce protected/unknown surfaces before both automatic and manual mutation.
- `ContextInvalidationObserver.swift`, `WordBuffer.swift`: purge on sleep/wake/session/display transitions and re-check permissions during runtime work.
- `ContentFreeDiagnosticReport.swift`, `verify-privacy-boundaries.sh`: bounded support export plus CI prohibition of clipboard, whole-field AX value, and runtime logging APIs.
- Adversarial tests cover the exact failing paths and performance/repetition limits.

## Cleanup and rollback

- Removed the misleading-success script, stale-state JSON, and three stress logs from `/private/tmp`.
- Terminated the deliberately hung child with SIGINT; no spawned process remains.
- No failed experiment or generated fixture remains in the repository.
- UltraQA state is cleared with `omx state clear` after the final report and checks.

## Residual risks

- Live TCC behavior in TextEdit, browsers, Electron apps, password managers, and Secure Keyboard Entry requires the user to grant persistent Input Monitoring and Accessibility consent. This cycle did not silently broaden host permissions.
- Browser accessibility identifiers can change across application releases. Unknown descriptors fail closed; the real-app matrix must be repeated for release candidates after consent is granted.
- Rapid next-key behavior deliberately favors no key loss: a moved caret cancels correction instead of suppressing/replaying the user's event.

## Evidence

- Commits: `baa567f`, `3c15edb`, `b06f3c3`.
- Full local test count: 60, zero failures.
- Stress timing: 100,000 token events in 0.018 seconds on the local arm64 host.
- Static gates: no forbidden runtime network, clipboard, whole-field AX, or logging APIs.
- Release bundle: built and ad-hoc signed by `scripts/build-app.sh release`.

ULTRAQA COMPLETE: Goal met after 1 cycle with MAN-01 retained as an explicit security-consent release gate.
