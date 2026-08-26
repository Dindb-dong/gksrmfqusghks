import XCTest

@testable import HanKeyCore

final class LearningRulesTests: XCTestCase {
  func testUpsertNormalizesAndReplacesExactPair() {
    var rules = LearningRuleSet()
    XCTAssertNotNil(rules.upsert(original: " gksrmffh ", replacement: " 한글로 ", behavior: .always))
    XCTAssertEqual(rules.behavior(original: "gksrmffh", replacement: "한글로"), .always)

    XCTAssertNotNil(rules.upsert(original: "gksrmffh", replacement: "한글로", behavior: .never))
    XCTAssertEqual(rules.entries.count, 1)
    XCTAssertEqual(rules.behavior(original: "gksrmffh", replacement: "한글로"), .never)
  }

  func testInvalidOrOversizedPairsAreRejected() {
    var rules = LearningRuleSet()
    XCTAssertNil(rules.upsert(original: "", replacement: "한글", behavior: .always))
    XCTAssertNil(rules.upsert(original: "same", replacement: "same", behavior: .always))
    XCTAssertNil(
      rules.upsert(
        original: String(repeating: "a", count: 65), replacement: "한글", behavior: .always)
    )
    XCTAssertTrue(rules.entries.isEmpty)
  }
}
