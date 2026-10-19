# Input handoff regression evidence

Date: 2026-10-19. Scope: standard-text automatic correction, manual conversion, and Undo.

## Cause and change

The previous standard-text backend selected a range, sent one synthetic key pair per character through the active IME, asynchronously checked only caret location, then selected the next source. Physical input could interleave; partial rollback could start another write before queued input finished. Source selection reported the requested source without readback.

The replacement backend uses one range-scoped AXSelectedText write, exact text/caret verification before and after source selection, and readback of the selected source. A dedicated event-tap thread briefly waits during the bounded handoff (including asynchronous AX acknowledgment) and returns the original event. The 80ms deadline releases input independently of main-thread responsiveness. Unknown/partial writes never trigger a second text write.

An initial temporary-tap implementation lost ordinal 0 of a 16-event burst when invalidated. It was rejected and replaced before delivery. The persistent callback gate passed the same uniquely numbered burst test without loss or duplication.

## Validation

- Full Swift suite with `HANKEY_RUN_INPUT_HANDOFF_INTEGRATION=1`: 173 tests passed, zero failures and no skipped tests.
- Real OS event tests: successful release, expired handoff while main thread blocked, and idle forwarding each preserved unique event ordinals 0 through 15 exactly once in order. A consuming tap prevented events from reaching another app.
- `scripts/check-native-input.sh`: independent AppKit NSTextView fixture passed English→Korean replacement/caret and subsequent Korean input; Korean→English replacement/caret and subsequent English input. The fixture used synthetic sample text and posted keys only to its own PID. Its temporary bundle was removed.
- Strict Swift formatting, `git diff --check`, network boundary scan, and privacy boundary scan passed.
- Privacy negative controls rejected selected-text reads, access outside the approved setter/capability-check site, whole-field AX access, and runtime logging.
- `swift build --configuration release --product HanKeyApp`: passed on this Apple Silicon host.

## Limits

These results do not certify every chat app's AXSelectedText support, formatting, IME, or focus behavior. Unsupported or uncertain AX operations fail closed; an uncertain setter can leave selection active and is surfaced as unavailable. The opt-in terminal backend remains a separate synthetic-event path. Intel/universal packaging, new notarization, and publication were not performed.

## Local test installation

At the user's request, the e13036d implementation was installed into `/Applications/HanKey.app` as local test version 1.0.2, build 3, on 2026-10-19. The arm64 Release binary was signed using the same Developer ID/team and designated requirement as the previous installation. Source revision/channel metadata identifies this local test build; it is not a published release or a newly notarized artifact.

The previous 1.0.1/build 2 bundle was archived at `~/Library/Application Support/HanKey-LocalInstallBackups/HanKey-1.0.1-build2-before-e13036d.zip`. ZIP integrity and the original executable's SHA-256 match were verified before removing the temporary old bundle. Existing preferences and Application Support data were preserved. The installed executable matched the staged signed build (SHA-256 `e7fb8656061fd824a041c2cfde9a84820070f0f048ac8226812fe57562d298fa`), strict code-signature validation passed, and the new process was confirmed running from the installed path.

The user will perform chat-app testing. No existing text document was used for installation verification.

## Local-install regression follow-up

The initial local build rejected normal web fields whose optional AXSubrole returned noValue. The installed app was restored to 1.0.1. An independent, task-owned WKWebView host reproduced that snapshot failure; accepting only optional missing subrole fixes that classification while role failures and secure fields remain protected. It also exposed the need to await accepted AX updates under the same handoff. Background tests cover delayed selection/text acknowledgment, changed original/selection/focus, cancellation and expiry, with no repeated text write.

Foreground integration runs were stopped at the user's request because they stole typing focus. Subsequent validation must remain in the background. The current changes do not establish complete WKWebView or Codex chat compatibility; do not treat the earlier self-process native fixture as that evidence.

The reviewed follow-up at `54786be` was installed as local-test 1.0.2/build 4 using the existing Developer ID. Startup used `open -g -j` to avoid activation; no further foreground fixtures or input-source tests ran. Strict signature/hash, one installed-path process, onboarding completion and automatic-correction preferences were verified. Executable SHA-256: `1346266340fadf43607defe61ce1bba76e9c7614bd1ff67d8df6470e6e59cb0b`. Background suite: 177 passed, 3 opt-in integration tests skipped, 0 failures; Release/format/privacy/network checks passed. Astra follow-up found no actionable code blockers. Codex chat behavior remains for user observation, not a claimed verified result.
