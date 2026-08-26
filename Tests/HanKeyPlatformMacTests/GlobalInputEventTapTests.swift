import Carbon.HIToolbox
import CoreGraphics
import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

final class GlobalInputEventTapTests: XCTestCase {
  func testInterpretsPhysicalLettersAndShift() throws {
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_G), flags: []),
      .printable(try XCTUnwrap(PhysicalKeyToken(ascii: "g")))
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_R), flags: .maskShift),
      .printable(try XCTUnwrap(PhysicalKeyToken(ascii: "R")))
    )
  }

  func testInterpretsBoundariesDeleteNavigationAndCommands() {
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_Space), flags: []),
      .boundary(.space)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Period), flags: []),
      .boundary(.punctuation)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_Delete), flags: []),
      .deleteBackward
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_LeftArrow), flags: []),
      .invalidate(.navigation)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand),
      .invalidate(.modifiedCommand)
    )
  }

  func testSyntheticMarkerRoundTripsOnCGEvent() throws {
    let event = try XCTUnwrap(
      CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true)
    )
    XCTAssertFalse(HanKeySyntheticEvent.isMarked(event))
    HanKeySyntheticEvent.mark(event)
    XCTAssertTrue(HanKeySyntheticEvent.isMarked(event))
  }
}
