import HanKeyCore
import XCTest

final class WordBufferTests: XCTestCase {
  func testCompletesOnlyTheCurrentBoundedWord() throws {
    var buffer = WordBuffer()
    for character in "gksrmffh" {
      let token = try XCTUnwrap(PhysicalKeyToken(ascii: character))
      XCTAssertEqual(buffer.handle(.printable(token), at: 1), .none)
    }

    XCTAssertEqual(
      buffer.handle(.boundary(.space), at: 2),
      .completed(BufferedWord(tokens: try tokens("gksrmffh")), boundary: .space)
    )
    XCTAssertTrue(buffer.tokens.isEmpty)
  }

  func testDeleteBackwardUpdatesTheInMemoryWord() throws {
    var buffer = WordBuffer()
    for token in try tokens("gksx") {
      _ = buffer.handle(.printable(token), at: 1)
    }
    XCTAssertEqual(buffer.handle(.deleteBackward, at: 2), .none)
    _ = buffer.handle(.printable(try XCTUnwrap(PhysicalKeyToken(ascii: "r"))), at: 3)

    guard case .completed(let word, _) = buffer.handle(.boundary(.returnKey), at: 4) else {
      return XCTFail("Expected a completed word")
    }
    XCTAssertEqual(word.qwerty, "gksr")
  }

  func testSecureInputPurgesAndNeverRestoresPreviousContent() throws {
    var buffer = WordBuffer()
    for token in try tokens("secret") {
      _ = buffer.handle(.printable(token), at: 1)
    }

    XCTAssertEqual(
      buffer.handle(.protectionChanged(isProtected: true), at: 2),
      .purged(.secureInput)
    )
    XCTAssertTrue(buffer.isProtected)
    XCTAssertTrue(buffer.tokens.isEmpty)
    XCTAssertEqual(
      buffer.handle(.printable(try XCTUnwrap(PhysicalKeyToken(ascii: "a"))), at: 3),
      .ignoredWhileProtected
    )

    XCTAssertEqual(buffer.handle(.protectionChanged(isProtected: false), at: 4), .none)
    XCTAssertFalse(buffer.isProtected)
    XCTAssertTrue(buffer.tokens.isEmpty)
  }

  func testFocusNavigationPointerAndCommandInvalidationsPurge() throws {
    for reason in [
      BufferInvalidationReason.applicationChanged, .focusChanged, .pointerInteraction, .navigation,
      .modifiedCommand, .inputSourceChanged, .systemStateChanged, .unknownKey,
    ] {
      var buffer = WordBuffer()
      _ = buffer.handle(
        .printable(try XCTUnwrap(PhysicalKeyToken(ascii: "a"))),
        at: 1
      )
      XCTAssertEqual(buffer.handle(.invalidate(reason), at: 2), .purged(reason))
      XCTAssertTrue(buffer.tokens.isEmpty)
    }
  }

  func testIdleTimeoutDropsOldContentBeforeStartingANewWord() throws {
    var buffer = WordBuffer(idleTimeoutNanoseconds: 10)
    _ = buffer.handle(.printable(try XCTUnwrap(PhysicalKeyToken(ascii: "a"))), at: 1)

    XCTAssertEqual(
      buffer.handle(.printable(try XCTUnwrap(PhysicalKeyToken(ascii: "b"))), at: 11),
      .purged(.idleTimeout)
    )
    XCTAssertEqual(BufferedWord(tokens: buffer.tokens).qwerty, "b")
  }

  func testCapacityOverflowPurgesEverything() throws {
    var buffer = WordBuffer(maximumTokenCount: 3)
    for token in try tokens("abc") {
      XCTAssertEqual(buffer.handle(.printable(token), at: 1), .none)
    }
    XCTAssertEqual(
      buffer.handle(
        .printable(try XCTUnwrap(PhysicalKeyToken(ascii: "d"))),
        at: 2
      ),
      .purged(.capacityExceeded)
    )
    XCTAssertTrue(buffer.tokens.isEmpty)
  }

  private func tokens(_ string: String) throws -> [PhysicalKeyToken] {
    try string.map { try XCTUnwrap(PhysicalKeyToken(ascii: $0)) }
  }
}
