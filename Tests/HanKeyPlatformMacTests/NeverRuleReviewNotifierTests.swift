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
      .keepExcluded
    )
    XCTAssertEqual(
      NeverRuleReviewNotifier.decision(
        for: NeverRuleReviewNotifier.rejectActionIdentifier
      ),
      .alwaysConvert
    )
    XCTAssertNil(NeverRuleReviewNotifier.decision(for: "unknown"))
  }

  func testActionTitlesDescribeTheirResultWithoutAcceptRejectAmbiguity() {
    let actions = NeverRuleReviewNotifier.makeCategory().actions

    XCTAssertEqual(actions.map(\.title), ["변환하지 않기", "계속 자동 변환"])
    XCTAssertFalse(actions.contains { $0.title == "수락" || $0.title == "거부" })
  }
}
