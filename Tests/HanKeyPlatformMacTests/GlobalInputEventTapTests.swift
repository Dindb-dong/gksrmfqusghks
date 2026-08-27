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
      .deleteBackward(.character)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_Delete), flags: .maskAlternate),
      .deleteBackward(.word)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_Delete), flags: .maskCommand),
      .deleteBackward(.line)
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

  func testInterpretsOnlyUnshiftedSlashAndHyphenAsCommandPrefixSymbols() {
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Slash), flags: []),
      .commandPrefixSymbol(.slash)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: []),
      .commandPrefixSymbol(.hyphen)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Slash), flags: .maskShift),
      .boundary(.questionMark)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskShift),
      .boundary(.punctuation)
    )
  }

  func testEveryPhysicalSpecialSymbolKeyCompletesTheBufferedWord() {
    let directSymbolKeys = [
      kVK_ANSI_Grave, kVK_ANSI_Equal, kVK_ANSI_LeftBracket,
      kVK_ANSI_RightBracket, kVK_ANSI_Backslash, kVK_ANSI_Semicolon, kVK_ANSI_Quote,
      kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_KeypadDecimal,
      kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadDivide,
      kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals, kVK_ISO_Section, kVK_JIS_Yen,
      kVK_JIS_Underscore, kVK_JIS_KeypadComma,
    ]
    for keyCode in directSymbolKeys {
      XCTAssertEqual(
        KeyEventInterpreter.interpret(keyCode: CGKeyCode(keyCode), flags: []),
        .boundary(.punctuation),
        "Expected key code \(keyCode) to complete the word"
      )
      XCTAssertEqual(
        KeyEventInterpreter.interpret(keyCode: CGKeyCode(keyCode), flags: .maskShift),
        .boundary(.punctuation),
        "Expected shifted key code \(keyCode) to complete the word"
      )
    }

    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskShift),
      .boundary(.punctuation)
    )
    XCTAssertEqual(
      KeyEventInterpreter.interpret(keyCode: CGKeyCode(kVK_ANSI_Slash), flags: .maskShift),
      .boundary(.questionMark)
    )
  }

  func testShiftedNumberRowSymbolsCompleteButDigitsInvalidate() {
    let numberKeys = [
      kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
      kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    for keyCode in numberKeys {
      XCTAssertEqual(
        KeyEventInterpreter.interpret(keyCode: CGKeyCode(keyCode), flags: .maskShift),
        .boundary(.punctuation),
        "Expected shifted number key code \(keyCode) to complete the word"
      )
      XCTAssertEqual(
        KeyEventInterpreter.interpret(keyCode: CGKeyCode(keyCode), flags: []),
        .invalidate(.unknownKey),
        "Expected digit key code \(keyCode) to keep failing closed"
      )
    }
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
