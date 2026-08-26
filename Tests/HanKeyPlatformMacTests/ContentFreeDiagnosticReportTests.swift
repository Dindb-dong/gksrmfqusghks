import XCTest

@testable import HanKeyPlatformMac

final class ContentFreeDiagnosticReportTests: XCTestCase {
  func testReportContainsOnlyBoundedNonContentState() throws {
    let report = ContentFreeDiagnosticReport(
      appVersion: "1.0.0",
      permissions: PermissionSnapshot(
        canMonitorInput: true,
        isAccessibilityTrusted: false,
        isSecureInputEnabled: true
      ),
      operationalState: "protected",
      learningRuleCount: 3,
      operatingSystem: "macOS test",
      architecture: "arm64"
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: report.encoded()) as? [String: Any]
    )

    XCTAssertEqual(
      Set(object.keys),
      [
        "schemaVersion", "appVersion", "operatingSystem", "architecture",
        "inputMonitoringGranted", "accessibilityGranted", "secureInputActive",
        "operationalState", "learningRuleCount",
      ]
    )
    let forbiddenKeys = ["text", "token", "word", "selection", "keyCode", "bundleIdentifier"]
    XCTAssertTrue(forbiddenKeys.allSatisfy { object[$0] == nil })
  }
}
