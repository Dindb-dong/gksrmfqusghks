import HanKeyPlatformMac
import XCTest

final class PermissionSnapshotTests: XCTestCase {
  func testReadyRequiresBothPermissionsAndNoSecureInput() {
    XCTAssertTrue(
      PermissionSnapshot(
        canMonitorInput: true,
        isAccessibilityTrusted: true,
        isSecureInputEnabled: false
      ).isReady
    )

    XCTAssertFalse(
      PermissionSnapshot(
        canMonitorInput: true,
        isAccessibilityTrusted: true,
        isSecureInputEnabled: true
      ).isReady
    )

    XCTAssertFalse(
      PermissionSnapshot(
        canMonitorInput: false,
        isAccessibilityTrusted: true,
        isSecureInputEnabled: false
      ).isReady
    )
  }
}
