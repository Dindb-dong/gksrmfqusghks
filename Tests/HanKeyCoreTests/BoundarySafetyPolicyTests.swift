import HanKeyCore
import XCTest

final class BoundarySafetyPolicyTests: XCTestCase {
  private let policy = BoundarySafetyPolicy()

  func testSentenceAndSymbolBoundariesRemainEligible() {
    for boundary in ["", " ", "?", "? ", "!", "~", "+", "$", "^", "()", "?! "] {
      XCTAssertTrue(policy.permitsAutomaticCorrection(boundary: boundary), boundary)
    }
  }

  func testAddressPathAndIdentifierContinuationsFailClosed() {
    for boundary in ["@", "/", "\\", ".", "_", "-", "@ ", "/ ", "... "] {
      XCTAssertFalse(policy.permitsAutomaticCorrection(boundary: boundary), boundary)
    }
  }
}
