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
  func testOnlyReplacementEventsBypassPhysicalInputHandoff() throws {
    let physical = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
    XCTAssertTrue(InputHandoff.shouldWait(for: physical))
    HanKeySyntheticEvent.mark(physical)
    XCTAssertFalse(InputHandoff.shouldWait(for: physical))
  }

  @MainActor
  func testPreparedReplacementCanDispatchOnlyOnce() {
    var dispatches = 0
    let prepared = PreparedTextReplacement { valid in
      guard valid() else { return false }
      dispatches += 1
      return true
    }
    XCTAssertTrue(prepared.perform(isStillValid: { true }))
    XCTAssertFalse(prepared.perform(isStillValid: { true }))
    XCTAssertEqual(dispatches, 1)
  }

}
