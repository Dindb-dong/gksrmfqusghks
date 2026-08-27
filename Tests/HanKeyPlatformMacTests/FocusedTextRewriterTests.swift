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
}
