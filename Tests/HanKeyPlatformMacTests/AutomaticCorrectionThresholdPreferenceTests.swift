import Foundation
import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class AutomaticCorrectionThresholdPreferenceTests: XCTestCase {
  func testDefaultsToExistingDecisionThresholdAndPersistsChanges() throws {
    let suiteName = "AutomaticCorrectionThresholdPreferenceTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = AutomaticCorrectionThresholdPreference(defaults: defaults)
    XCTAssertEqual(first.value, AutomaticCorrectionThreshold.defaultValue)

    first.setValue(84)
    XCTAssertEqual(AutomaticCorrectionThresholdPreference(defaults: defaults).value, 84)
  }

  func testStoredAndWrittenValuesAreClamped() throws {
    let suiteName = "AutomaticCorrectionThresholdPreferenceTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(10, forKey: AutomaticCorrectionThresholdPreference.key)
    let preference = AutomaticCorrectionThresholdPreference(defaults: defaults)
    XCTAssertEqual(preference.value, 50)

    preference.setValue(150)
    XCTAssertEqual(defaults.integer(forKey: AutomaticCorrectionThresholdPreference.key), 100)
  }
}
