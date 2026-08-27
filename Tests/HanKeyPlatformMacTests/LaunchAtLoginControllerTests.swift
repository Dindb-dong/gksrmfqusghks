import ServiceManagement
import XCTest

@testable import HanKeyPlatformMac

final class LaunchAtLoginControllerTests: XCTestCase {
  func testMapsEveryKnownServiceStatusWithoutTreatingApprovalAsEnabled() {
    XCTAssertEqual(LaunchAtLoginController.map(.notRegistered), .notRegistered)
    XCTAssertEqual(LaunchAtLoginController.map(.enabled), .enabled)
    XCTAssertEqual(LaunchAtLoginController.map(.requiresApproval), .requiresApproval)
    XCTAssertEqual(LaunchAtLoginController.map(.notFound), .repairRequired)
    XCTAssertTrue(LaunchAtLoginStatus.enabled.isEnabled)
    XCTAssertFalse(LaunchAtLoginStatus.requiresApproval.isEnabled)
  }
}
