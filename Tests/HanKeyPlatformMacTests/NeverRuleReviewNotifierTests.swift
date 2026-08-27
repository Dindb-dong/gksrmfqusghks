import XCTest

@testable import HanKeyPlatformMac

final class NeverRuleReviewNotifierTests: XCTestCase {
  func testNotificationPayloadContainsRuleIDButNoTypedContent() throws {
    let ruleID = UUID()
    let content = NeverRuleReviewNotifier.makeContent(ruleID: ruleID)
    let rendered = content.title + content.body + content.subtitle

    XCTAssertEqual(content.categoryIdentifier, NeverRuleReviewNotifier.categoryIdentifier)
    XCTAssertEqual(content.userInfo.count, 1)
    XCTAssertEqual(
      content.userInfo[NeverRuleReviewNotifier.ruleIDKey] as? String, ruleID.uuidString)
    XCTAssertFalse(rendered.contains("ㅣㄷ퍄ㅐㄴㅁ"))
    XCTAssertFalse(rendered.contains("leviosa"))
  }

  func testActionsMapToExplicitReviewDecisions() {
    XCTAssertEqual(
      NeverRuleReviewNotifier.decision(
        for: NeverRuleReviewNotifier.acceptActionIdentifier
      ),
      .accept
    )
    XCTAssertEqual(
      NeverRuleReviewNotifier.decision(
        for: NeverRuleReviewNotifier.rejectActionIdentifier
      ),
      .rejectAndAlwaysConvert
    )
    XCTAssertNil(NeverRuleReviewNotifier.decision(for: "unknown"))
  }
}
