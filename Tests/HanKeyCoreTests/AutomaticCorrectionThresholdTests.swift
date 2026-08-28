import HanKeyCore
import XCTest

final class AutomaticCorrectionThresholdTests: XCTestCase {
  func testDefaultPreservesExistingAutomaticMargin() {
    let threshold = AutomaticCorrectionThreshold(AutomaticCorrectionThreshold.defaultValue)

    XCTAssertEqual(threshold.value, 75)
    XCTAssertEqual(threshold.automaticMargin, 1.25, accuracy: 0.000_001)
  }

  func testValueClampsToSupportedRange() {
    XCTAssertEqual(AutomaticCorrectionThreshold(20).value, 50)
    XCTAssertEqual(AutomaticCorrectionThreshold(120).value, 100)
  }

  func testLowerValuesAreMoreAggressiveAndHigherValuesMoreConservative() {
    let aggressive = AutomaticCorrectionThreshold(50).automaticMargin
    let recommended = AutomaticCorrectionThreshold(80).automaticMargin
    let conservative = AutomaticCorrectionThreshold(100).automaticMargin

    XCTAssertLessThan(aggressive, recommended)
    XCTAssertLessThan(recommended, conservative)
  }
}
