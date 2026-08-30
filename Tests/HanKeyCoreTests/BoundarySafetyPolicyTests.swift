import HanKeyCore
import XCTest

final class BoundarySafetyPolicyTests: XCTestCase {
  private let policy = BoundarySafetyPolicy()

  func testSentenceAndSymbolBoundariesRemainEligible() {
    for boundary in ["", " ", "!", "~", "+", "$", "^", "_", "-", "()", "!! "] {
      XCTAssertTrue(policy.permitsAutomaticCorrection(boundary: boundary), boundary)
      XCTAssertFalse(policy.requiresContinuationCheck(boundary: boundary), boundary)
    }
    for boundary in ["?", "? "] {
      XCTAssertTrue(
        policy.permitsAutomaticCorrection(
          boundary: boundary,
          allowsNaturalQuestionMark: true
        ),
        boundary
      )
    }
  }

  func testAmbiguousContinuationBoundariesRequireASettlingWindow() {
    for boundary in ["@", "/", "\\", ".", "?", "@ ", "/ ", "? ", "... "] {
      XCTAssertFalse(policy.permitsAutomaticCorrection(boundary: boundary), boundary)
      XCTAssertTrue(policy.requiresContinuationCheck(boundary: boundary), boundary)
      XCTAssertTrue(
        policy.permitsAutomaticCorrection(
          boundary: boundary,
          hasSettledAmbiguousBoundary: true
        ),
        boundary
      )
    }
  }
}
