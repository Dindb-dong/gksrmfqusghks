import XCTest

@testable import HanKeyCore

final class RepeatedInputGuardTests: XCTestCase {
  func testImmediateRepeatIsNotSuppressedWithoutConfirmedDeletion() throws {
    let word = try bufferedWord("skdltm")
    var guardrail = RepeatedInputGuard()

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: word))
    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: word))
  }

  func testConfirmedDeletionThenSameInputBecomesSessionSuppressed() throws {
    let word = try bufferedWord("skdltm")
    var guardrail = RepeatedInputGuard()

    guardrail.armSuppressionAfterDeletion(for: word)

    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: word))
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: word))
  }

  func testDifferentNextWordConsumesDeletionConfirmedComparison() throws {
    let corrected = try bufferedWord("skdltm")
    let different = try bufferedWord("gksrmf")
    var guardrail = RepeatedInputGuard()

    guardrail.armSuppressionAfterDeletion(for: corrected)

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: different))
    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: corrected))
  }

  func testShiftedTypingIsNotTheSamePhysicalSequence() throws {
    let lowercase = try bufferedWord("skdltm")
    let shifted = try bufferedWord("Skdltm")
    var guardrail = RepeatedInputGuard()

    guardrail.armSuppressionAfterDeletion(for: lowercase)

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: shifted))
  }

  func testCommandPrefixIsPartOfRepeatedInputIdentity() throws {
    let plain = try bufferedWord("compact")
    let slash = BufferedWord(tokens: plain.tokens, leadingCommandPrefix: .slash)
    var guardrail = RepeatedInputGuard()

    guardrail.armSuppressionAfterDeletion(for: slash)

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: plain))
    guardrail.armSuppressionAfterDeletion(for: slash)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: slash))
  }

  func testSuppressionMemoryIsBoundedAndEvictsOldest() throws {
    let first = try bufferedWord("skdltm")
    let second = try bufferedWord("gksrmf")
    var guardrail = RepeatedInputGuard(maximumSuppressedWordCount: 1)

    guardrail.armSuppressionAfterDeletion(for: first)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: first))
    guardrail.armSuppressionAfterDeletion(for: second)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: second))

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: first))
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: second))
  }

  func testResetClearsPendingAndSuppressedWords() throws {
    let word = try bufferedWord("skdltm")
    var guardrail = RepeatedInputGuard()
    guardrail.armSuppressionAfterDeletion(for: word)
    XCTAssertTrue(guardrail.shouldSuppressCorrection(for: word))

    guardrail.reset()

    XCTAssertFalse(guardrail.shouldSuppressCorrection(for: word))
  }

  func testExtraDeletionCancelsPendingComparison() throws {
    let word = try bufferedWord("skdltm")
    var guardrail = RepeatedInputGuard()
    guardrail.armSuppressionAfterDeletion(for: word)

    guardrail.cancelPendingComparison()

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
