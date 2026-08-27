import XCTest

@testable import HanKeyCore

final class RepeatedInputGuardTests: XCTestCase {
  func testImmediateRepeatBecomesSessionSuppressed() throws {
    let word = try bufferedWord("skdltm")
    var guardrail = RepeatedInputGuard()

    guardrail.recordCorrection(for: word)

    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: word))
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: word))
  }

  func testDifferentNextWordConsumesPendingComparison() throws {
    let corrected = try bufferedWord("skdltm")
    let different = try bufferedWord("gksrmf")
    var guardrail = RepeatedInputGuard()

    guardrail.recordCorrection(for: corrected)

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: different))
    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: corrected))
  }

  func testShiftedTypingIsNotTheSamePhysicalSequence() throws {
    let lowercase = try bufferedWord("skdltm")
    let shifted = try bufferedWord("Skdltm")
    var guardrail = RepeatedInputGuard()

    guardrail.recordCorrection(for: lowercase)

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: shifted))
  }

  func testSuppressionMemoryIsBoundedAndEvictsOldest() throws {
    let first = try bufferedWord("skdltm")
    let second = try bufferedWord("gksrmf")
    var guardrail = RepeatedInputGuard(maximumSuppressedWordCount: 1)

    guardrail.recordCorrection(for: first)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: first))
    guardrail.recordCorrection(for: second)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: second))

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: first))
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: second))
  }

  func testResetClearsPendingAndSuppressedWords() throws {
    let word = try bufferedWord("skdltm")
    var guardrail = RepeatedInputGuard()
    guardrail.recordCorrection(for: word)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: word))

    guardrail.reset()

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: word))
  }

  private func bufferedWord(_ ascii: String) throws -> BufferedWord {
    BufferedWord(
      tokens: try ascii.map { character in
        try XCTUnwrap(PhysicalKeyToken(ascii: character))
      }
    )
  }
}
