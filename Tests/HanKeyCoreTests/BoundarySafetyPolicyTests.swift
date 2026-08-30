import HanKeyCore
import XCTest

final class BoundarySafetyPolicyTests: XCTestCase {
  private let policy = BoundarySafetyPolicy()

  func testSentenceAndSymbolBoundariesRemainEligible() {
    for boundary in ["", " ", "!", "~", "+", "$", "^", "_", "-", "()", "!! "] {
      XCTAssertTrue(policy.permitsAutomaticCorrection(boundary: boundary), boundary)
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

  func testAddressPathAndIdentifierContinuationsFailClosed() {
    for boundary in ["@", "/", "\\", ".", "?", "@ ", "/ ", "? ", "... "] {
      XCTAssertFalse(policy.permitsAutomaticCorrection(boundary: boundary), boundary)
    }
  }
}
