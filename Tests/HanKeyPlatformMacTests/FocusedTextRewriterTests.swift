import ApplicationServices
import XCTest

@testable import HanKeyPlatformMac

final class FocusedTextRewriterTests: XCTestCase {
  func testUnicodeEventsAreSplitAtUserVisibleCharacterBoundaries() {
    XCTAssertEqual(
      UnicodeEventText.segments("한글로? "),
      ["한", "글", "로", "?", " "]
    )
  }

  func testUnicodeEventsKeepComposedCharactersTogether() {
    XCTAssertEqual(
      UnicodeEventText.segments("👩🏽‍💻é"),
      ["👩🏽‍💻", "é"]
    )
  }
  @MainActor
  func testStaleSelectionRejectsBeforeSelectingOrWriting() async {
    var selections = 0
    var writes = 0
    let result = await SelectedTextMutation.perform(
      expectedSelection: TextUTF16Range(location: 8, length: 0),
      targetRange: TextUTF16Range(location: 0, length: 8),
      isStillValid: { true }, selection: { TextUTF16Range(location: 9, length: 0) },
      select: { _ in
        selections += 1
        return .success
      }, originalIsUnchanged: { true },
      write: {
        writes += 1
        return .success
      })
    XCTAssertFalse(result)
    XCTAssertEqual(selections, 0)
    XCTAssertEqual(writes, 0)
  }

  @MainActor
  func testDefiniteRejectionRestoresOnlyUnchangedSelectionAndText() async {
    let originalSelection = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    for unchanged in [true, false] {
      var selection = originalSelection
      var selections: [TextUTF16Range] = []
      let result = await SelectedTextMutation.perform(
        expectedSelection: originalSelection, targetRange: target,
        isStillValid: { true }, selection: { selection },
        select: {
          selection = $0
          selections.append($0)
          return .success
        },
        originalIsUnchanged: { unchanged }, write: { .attributeUnsupported })
      XCTAssertFalse(result)
      XCTAssertEqual(selections, unchanged ? [target, originalSelection] : [target])
    }
  }

  @MainActor
  func testAmbiguousTimeoutNeverStartsRecoveryMutation() async {
    let originalSelection = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    var selection = originalSelection
    var selections: [TextUTF16Range] = []
    let result = await SelectedTextMutation.perform(
      expectedSelection: originalSelection, targetRange: target,
      isStillValid: { true }, selection: { selection },
      select: {
        selection = $0
        selections.append($0)
        return .success
      },
      originalIsUnchanged: { true }, write: { .cannotComplete })
    XCTAssertFalse(result)
    XCTAssertEqual(selections, [target])
  }

  @MainActor
  func testDelayedSelectionAcknowledgmentWritesOnce() async {
    let original = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    var current = original
    var selections = 0
    var writes = 0
    let result = await SelectedTextMutation.perform(
      expectedSelection: original, targetRange: target,
      isStillValid: { true }, selection: { current },
      select: { _ in
        selections += 1
        return .success
      },
      originalIsUnchanged: { true },
      write: {
        writes += 1
        return .success
      },
      delay: { current = target })
    XCTAssertTrue(result)
    XCTAssertEqual(selections, 1)
    XCTAssertEqual(writes, 1)
  }

  @MainActor
  func testPendingSelectionRejectsUnexpectedSelectionAndChangedText() async {
    let original = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    for unexpectedSelection in [true, false] {
      var current = original
      var writes = 0
      let result = await SelectedTextMutation.perform(
        expectedSelection: original, targetRange: target,
        isStillValid: { true }, selection: { current }, select: { _ in .success },
        originalIsUnchanged: { false },
        write: {
          writes += 1
          return .success
        },
        delay: { current = unexpectedSelection ? TextUTF16Range(location: 3, length: 0) : target })
      XCTAssertFalse(result)
      XCTAssertEqual(writes, 0)
    }
  }

  @MainActor
  func testExpiredHandoffDuringSelectionAcknowledgmentNeverWrites() async {
    let original = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    var valid = true
    var writes = 0
    let result = await SelectedTextMutation.perform(
      expectedSelection: original, targetRange: target,
      isStillValid: { valid }, selection: { original }, select: { _ in .success },
      originalIsUnchanged: { true },
      write: {
        writes += 1
        return .success
      },
      delay: { valid = false })
    XCTAssertFalse(result)
    XCTAssertEqual(writes, 0)
  }

  @MainActor
  func testCancelledTaskNeverSelectsOrWrites() async {
    let result = await Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      var mutations = 0
      let accepted = await SelectedTextMutation.perform(
        expectedSelection: TextUTF16Range(location: 8, length: 0),
        targetRange: TextUTF16Range(location: 0, length: 8),
        isStillValid: { true }, selection: { TextUTF16Range(location: 8, length: 0) },
        select: { _ in
          mutations += 1
          return .success
        }, originalIsUnchanged: { true },
        write: {
          mutations += 1
          return .success
        })
      return (accepted, mutations)
    }.value
    XCTAssertFalse(result.0)
    XCTAssertEqual(result.1, 0)
  }

}
