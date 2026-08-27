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
    XCTAssertEqual(buffer.handle(.deleteBackward(.character), at: 2), .none)
    _ = buffer.handle(.printable(try XCTUnwrap(PhysicalKeyToken(ascii: "r"))), at: 3)

    guard case .completed(let word, _) = buffer.handle(.boundary(.returnKey), at: 4) else {
      return XCTFail("Expected a completed word")
    }
    XCTAssertEqual(word.qwerty, "gksr")
  }

  func testCapturesSupportedLeadingCommandPrefixesWithoutAddingThemToToken() throws {
    let cases: [(observations: [BufferObservation], expected: LeadingCommandPrefix)] = [
      ([.commandPrefixSymbol(.slash)], .slash),
      ([.commandPrefixSymbol(.hyphen)], .singleHyphen),
      ([.commandPrefixSymbol(.hyphen), .commandPrefixSymbol(.hyphen)], .doubleHyphen),
    ]

    for testCase in cases {
      var buffer = WordBuffer()
      for observation in testCase.observations {
        XCTAssertEqual(buffer.handle(observation, at: 1), .none)
      }
      for token in try tokens("compact") {
        XCTAssertEqual(buffer.handle(.printable(token), at: 2), .none)
      }

      XCTAssertEqual(
        buffer.handle(.boundary(.space), at: 3),
        .completed(
          BufferedWord(
            tokens: try tokens("compact"),
            leadingCommandPrefix: testCase.expected
          ),
          boundary: .space
        )
      )
    }
  }

  func testNestedOrRepeatedPrefixesFailClosed() throws {
    for testCase in [
      (
        observations: [
          BufferObservation.commandPrefixSymbol(.slash), .commandPrefixSymbol(.slash),
        ],
        results: [WordBufferAction.none, .purged(.unknownKey)]
      ),
      (
        observations: [
          BufferObservation.commandPrefixSymbol(.hyphen), .commandPrefixSymbol(.hyphen),
          .commandPrefixSymbol(.hyphen),
        ],
        results: [WordBufferAction.none, .none, .purged(.unknownKey)]
      ),
      (
        observations: [
          BufferObservation.commandPrefixSymbol(.slash), .commandPrefixSymbol(.hyphen),
        ],
        results: [WordBufferAction.none, .purged(.unknownKey)]
      ),
    ] {
      var buffer = WordBuffer()
      for (index, observation) in testCase.observations.enumerated() {
        XCTAssertEqual(
          buffer.handle(observation, at: UInt64(index + 1)),
          testCase.results[index]
        )
      }
      XCTAssertNil(buffer.leadingCommandPrefix)
      for token in try tokens("compact") {
        _ = buffer.handle(.printable(token), at: 3)
      }
      guard case .completed(let word, _) = buffer.handle(.boundary(.space), at: 4) else {
        return XCTFail("Expected an ordinary word after invalid prefix")
      }
      XCTAssertNil(word.leadingCommandPrefix)
    }
  }

  func testSlashInsideATokenDoesNotBecomeTheNextSegmentPrefix() throws {
    var buffer = WordBuffer()
    _ = buffer.handle(.commandPrefixSymbol(.slash), at: 1)
    for token in try tokens("usr") {
      _ = buffer.handle(.printable(token), at: 2)
    }

    XCTAssertEqual(
      buffer.handle(.commandPrefixSymbol(.slash), at: 3),
      .completed(
        BufferedWord(tokens: try tokens("usr"), leadingCommandPrefix: .slash),
        boundary: .punctuation
      )
    )
    for token in try tokens("compact") {
      _ = buffer.handle(.printable(token), at: 4)
    }
    guard case .completed(let word, _) = buffer.handle(.boundary(.space), at: 5) else {
      return XCTFail("Expected the path segment to complete")
    }
    XCTAssertNil(word.leadingCommandPrefix)
  }

  func testWordAndLineDeletionPurgeUnknownBufferExtent() throws {
    for deletion in [BackwardDeletionKind.word, .line] {
      var buffer = WordBuffer()
      for token in try tokens("gksrmffh") {
        _ = buffer.handle(.printable(token), at: 1)
      }
      XCTAssertEqual(
        buffer.handle(.deleteBackward(deletion), at: 2),
        .purged(.modifiedCommand)
      )
      XCTAssertTrue(buffer.tokens.isEmpty)
    }
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
