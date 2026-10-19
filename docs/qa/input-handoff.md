> Historical verification below includes failed AXSelectedText candidates. The latest follow-up restores the 1.0.1 insertion transport while retaining input waiting; earlier fixture passes are not evidence for the current Codex runtime.

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

## Keep-gate transport correction

The user confirmed 1.0.1 works and build4 leaves the original selected with an input pause. The original was restored again in the background. The input-wait requirement remains: removing it would leave the original rapid-typing/source race unresolved.

Current code prepares the original PID-directed, character-sized marked Unicode events before beginning the same 80ms gate. It then validates and selects the range and posts once without a selection-ack wait. Production replacement posts directly to the target PID downstream of the session gate; the callback also excludes marked events from waiting. The marker predicate alone does not allow events queued behind an already-blocked callback to overtake it. Exact text/caret acknowledgment precedes source selection; a pre-registered, immediately delivered TIS source-change notification plus source ID readback precedes post-switch text verification and input release. No partial rollback or source toggling is allowed. The AXSelectedText setter and its privacy exception were removed. Timeouts are scoped to the target application/element, not process-global.

Background tests use fake sources/notification centers and controlled handoffs. They cover both directions, prepare-before-gate, delayed source/text acknowledgment, one-shot insertion, synthetic bypass, expiry and single gate release. No foreground fixture, actual source change, or global injection test was run for this follow-up. Effective Codex IME behavior remains unverified; a system source notification is not an app-specific IME acknowledgment.

Follow-up background validation: 180 tests total, 177 passed, 3 real-event opt-in tests skipped, 0 failures. Release build, strict formatting, diff check, privacy and runtime network scans passed. Astra reviewed the keep-gate design and follow-up expected-original validation and found no further concrete code blocker. The single gate remains 80ms with a 15ms pre-mutation AX/posting reserve; no deadline is restarted per stage.

The keep-gate correction `b7d282e` was installed as local-test 1.0.2/build 5 using the existing Developer ID and background-only `open -g -j` launch. Installed-path process, version/source metadata and signed executable hash were verified: `e84f8bd32cd3bb2dac55de1092cf43c07f6070d87c66d0d190bf320bfde34d2b`. Original 1.0.1 backup and saved settings remain intact. This was not a new notarized/public release. No foreground, source-switch or global injection testing was performed; effective Codex IME remains for user observation.

## Build 5 user-observed failure and native-route investigation

The user observed English-to-Korean correction followed by raw English typing despite the Korean source indicator, so build 5 has not resolved the original effective-IME activation requirement. No source readback or notification test should be reported as end-to-end success.

Primary references now establish a relevant existing failure family:

- Karabiner's own documentation explicitly warns about CJKV input-mode selection and recommends the native source-switch shortcut: https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/select-input-source/
- The instrumented follow-up on Rime issue 1162 reports activation followed by deactivation after cross-process TIS selection, including tested Apple Chinese IMEs; it does not directly establish Apple's Korean behavior on this machine: https://github.com/rime/squirrel/issues/1162
- macism documents the same CJKV indicator/actual-input mismatch; its focus-changing workaround is incompatible with this user's no-focus-disruption requirement: https://github.com/laishulu/macism

A task-owned background-only own-PID probe (no window, no global tap, no source changes) found that proxy-posted synthetic events were not delivered downstream during a held callback; they proceeded after return. Thus proxy ordering is not an acknowledgment or a reliable route around a blocked callback.

The standalone NativeHotkeyRoutingProbe.swift is prepared and compile-checked only. It compares session versus annotated posting using exclusively registered, unmodified F20 and a consuming annotated tap; it neither switches the input source nor activates a window. A positive result would establish only Carbon hotkey route reachability, not Korean activation or Codex compatibility. Automatic approval review rejected execution because global taps/shortcut registration/session events can interfere with the user's input, and explicit authorization for that test was missing. Do not run it without that authorization. Production code and installed build 5 are unchanged by this investigation.

### One authorized routing run

After the user explicitly authorized one run, the prepared probe executed once. Output: `session own hotkey hits 0`; `INCONCLUSIVE session calibration; annotated pair not posted` (exit 1). It did not post the second pair and was not retried. This is not evidence that annotated native shortcut posting works or fails. Static follow-up identified that pumping Foundation RunLoop alone does not establish Carbon event dispatch to the registered application handler; the consuming sink may also affect routing. Therefore this calibration cannot justify a production change. Any further global-event experiment needs new explicit authorization; the one-run authorization is consumed. Installed build 5 and production source remain unchanged. The original effective Korean IME problem is unresolved.

## Native shortcut with nonblocking input wait

The revised standalone probe first verifies Carbon dispatch using an event in its own process queue. With explicit background-test authorization, the routing run produced session hotkey hits 1 / sink 0, annotated hits 0 / sink 2, and unchanged frontmost PID. A bounded annotated-callback hold delayed the hotkey notification until after release; moving the same blocking wait was not justified. A further nonblocking session-proxy probe produced hotkey hits 1 / sink 0 and unchanged frontmost PID. These are routing observations, not Korean IME or Codex compatibility proof. None switched the input source or read text.

Production now waits through a bounded in-memory FIFO while callbacks return immediately. Queue ownership is transferred once using same-callback proxy prefix posting. A content-free control wake is idempotent and bounded retries never resend user events. Actual tap failure clears ownership, disables future corrections, and directly releases unposted events once; strict FIFO is not claimed after OS filtering failure.

Native source commands start and clean up through the same callback, with a private source and prebuilt Control-down / Space-down / Space-up / Control-up events. A worker timer requests cleanup after 20ms; emergency paths force the same one-shot cleanup before physical release. A main-thread preflight verifies exactly ABC + two-set Korean and enabled Control-Space shortcut60 before text selection. Read-only inspection on this machine confirmed those settings. Known context invalidation cancels a queued command; expected source-change notifications after starting our own command are distinguished.

All repeating regression tests now use the test process's PID for real taps, posts and consuming sinks. No foreground test window, activation, existing document/chat reads, or actual source switches are required. Background cases cover ordinary completion, exact once/in-order release, modifier preservation, main-thread-blocked timeout, lost wake retry, synthetic progress, stop, and native cleanup before physical delivery for completion/cancellation/expiry/overflow/stop. Test counts and final build/install evidence are recorded after final review below. A native shortcut and source notification still do not establish successful effective Korean typing in Codex; final user observation remains required. A build5-induced pre-existing desynchronization may require the user's normal manual CapsLock reset before validating prevention of new failures.

Final candidate validation: 200 tests passed, zero failed or skipped, including 13 real own-PID handoff cases and a pure lifecycle regression proving cancellation/shutdown before first use never constructs the global tap. Release compilation, strict Swift formatting, privacy/network boundary scans and diff checks passed. Local GPT-6 Astra high review approved the current patch with no remaining actionable finding after cleanup ordering, context cancellation and lazy lifecycle fixes. This approval and the background routing probes do not verify effective Korean typing in Codex.
