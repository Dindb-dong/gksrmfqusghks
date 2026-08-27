import Foundation
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class AutomaticCorrectionPreferenceTests: XCTestCase {
  func testExplicitOptInPersistsAcrossPreferenceInstancesAndCanBeDisabled() throws {
    let suiteName = "AutomaticCorrectionPreferenceTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = AutomaticCorrectionPreference(defaults: defaults)
    XCTAssertFalse(first.isEnabled)
    first.setEnabled(true)

    let relaunched = AutomaticCorrectionPreference(defaults: defaults)
    XCTAssertTrue(relaunched.isEnabled)
    relaunched.setEnabled(false)
    XCTAssertFalse(AutomaticCorrectionPreference(defaults: defaults).isEnabled)
  }
}
