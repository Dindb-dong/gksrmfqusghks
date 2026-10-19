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
  func testStaleSelectionRejectsBeforeSelectingOrWriting() {
    var selections = 0
    var writes = 0
    let result = SelectedTextMutation.perform(
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
  func testDefiniteRejectionRestoresOnlyUnchangedSelectionAndText() {
    let originalSelection = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    for unchanged in [true, false] {
      var selection = originalSelection
      var selections: [TextUTF16Range] = []
      let result = SelectedTextMutation.perform(
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
  func testAmbiguousTimeoutNeverStartsRecoveryMutation() {
    let originalSelection = TextUTF16Range(location: 8, length: 0)
    let target = TextUTF16Range(location: 0, length: 8)
    var selection = originalSelection
    var selections: [TextUTF16Range] = []
    let result = SelectedTextMutation.perform(
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

}
