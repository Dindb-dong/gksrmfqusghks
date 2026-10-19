# Input handoff regression evidence

Date: 2026-10-19. Scope: standard-text automatic correction, manual conversion, and Undo.

## Cause and change

The previous standard-text backend selected a range, sent one synthetic key pair per character through the active IME, asynchronously checked only caret location, then selected the next source. Physical input could interleave; partial rollback could start another write before queued input finished. Source selection reported the requested source without readback.

The replacement backend uses one range-scoped AXSelectedText write, exact text/caret verification before and after source selection, and readback of the selected source. A dedicated event-tap thread briefly waits during the synchronous handoff and returns the original event. The 80ms deadline releases input independently of main-thread responsiveness. Unknown/partial writes never trigger a second text write.

An initial temporary-tap implementation lost ordinal 0 of a 16-event burst when invalidated. It was rejected and replaced before delivery. The persistent callback gate passed the same uniquely numbered burst test without loss or duplication.

## Validation

- Full Swift suite with `HANKEY_RUN_INPUT_HANDOFF_INTEGRATION=1`: 173 tests passed, zero failures and no skipped tests.
- Real OS event tests: successful release, expired handoff while main thread blocked, and idle forwarding each preserved unique event ordinals 0 through 15 exactly once in order. A consuming tap prevented events from reaching another app.
- `scripts/check-native-input.sh`: independent AppKit NSTextView fixture passed English→Korean replacement/caret and subsequent Korean input; Korean→English replacement/caret and subsequent English input. The fixture used synthetic sample text and posted keys only to its own PID. Its temporary bundle was removed.
- Strict Swift formatting, `git diff --check`, network boundary scan, and privacy boundary scan passed.
- Privacy negative controls rejected selected-text reads, access outside the approved setter/capability-check site, whole-field AX access, and runtime logging.
- `swift build --configuration release --product HanKeyApp`: passed on this Apple Silicon host.

## Limits

These results do not certify every chat app's AXSelectedText support, formatting, IME, or focus behavior. Unsupported or uncertain AX operations fail closed; an uncertain setter can leave selection active and is surfaced as unavailable. The opt-in terminal backend remains a separate synthetic-event path. Intel/universal packaging, signed installation, notarization, and publication were not performed.
