import ApplicationServices
import XCTest

@testable import HanKeyPlatformMac

final class FocusedElementSecurityInspectorTests: XCTestCase {
  func testAbsentOptionalSubroleIsNotAnIPCFailure() {
    XCTAssertTrue(
      FocusedElementSecurityInspector.isSecurityReadReliable(role: .success, subrole: .noValue))
    XCTAssertFalse(
      FocusedElementSecurityInspector.isSecurityReadReliable(role: .noValue, subrole: .noValue))
    XCTAssertEqual(
      FocusedElementSecurityInspector.classify(
        AccessibilityElementDescriptor(role: kAXTextAreaRole as String, subrole: nil)), .editable)
    XCTAssertEqual(
      FocusedElementSecurityInspector.classify(
        AccessibilityElementDescriptor(
          role: kAXTextFieldRole as String, subrole: kAXSecureTextFieldSubrole as String)), .secure)
  }

  func testTimedOutSecurityAttributesFailClosed() {
    XCTAssertTrue(
      FocusedElementSecurityInspector.isSecurityReadReliable(role: .success, subrole: .success))
    XCTAssertTrue(
      FocusedElementSecurityInspector.isSecurityReadReliable(
        role: .success, subrole: .attributeUnsupported))
    XCTAssertFalse(
      FocusedElementSecurityInspector.isSecurityReadReliable(
        role: .success, subrole: .cannotComplete))
    XCTAssertFalse(
      FocusedElementSecurityInspector.isSecurityReadReliable(
        role: .cannotComplete, subrole: .success))
    XCTAssertFalse(
      FocusedElementSecurityInspector.isSecurityReadReliable(
        role: .success, subrole: .invalidUIElement))
  }

  func testSecureSubroleAlwaysWins() {
    XCTAssertEqual(
      FocusedElementSecurityInspector.classify(
        AccessibilityElementDescriptor(
          role: kAXTextFieldRole as String,
          subrole: kAXSecureTextFieldSubrole as String
        )
      ),
      .secure
    )
  }

  func testEditableAndUnknownRolesFailToTheirExplicitStates() {
    XCTAssertEqual(
      FocusedElementSecurityInspector.classify(
        AccessibilityElementDescriptor(role: kAXTextAreaRole as String, subrole: nil)
      ),
      .editable
    )
    XCTAssertEqual(
      FocusedElementSecurityInspector.classify(
        AccessibilityElementDescriptor(role: kAXButtonRole as String, subrole: nil)
      ),
      .nonEditable
    )
    XCTAssertEqual(
      FocusedElementSecurityInspector.classify(
        AccessibilityElementDescriptor(role: nil, subrole: nil)
      ),
      .unavailable
    )
  }

  func testFocusTrackerDetectsCrossFieldChangesWithoutPersistingContent() {
    var tracker = FocusIdentityTracker()
    let first = FocusedElementIdentity(processID: 10, elementHash: 100)
    let second = FocusedElementIdentity(processID: 10, elementHash: 200)

    XCTAssertFalse(tracker.update(first))
    XCTAssertFalse(tracker.update(first))
    XCTAssertTrue(tracker.update(second))
    tracker.reset()
    XCTAssertFalse(tracker.update(first))
  }
}
