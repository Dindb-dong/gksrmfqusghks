import Foundation
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class TerminalCorrectionPreferenceTests: XCTestCase {
  func testStartsDisabledAndPersistsExplicitOptIn() throws {
    let suiteName = "TerminalCorrectionPreferenceTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let preference = TerminalCorrectionPreference(defaults: defaults)
    XCTAssertFalse(preference.isEnabled)
    preference.setEnabled(true)
    XCTAssertTrue(TerminalCorrectionPreference(defaults: defaults).isEnabled)
  }
}
