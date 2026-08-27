import Foundation
@preconcurrency import UserNotifications

public enum NeverRuleReviewDecision: Equatable, Sendable {
  case accept
  case rejectAndAlwaysConvert
}

public final class NeverRuleReviewNotifier: NSObject, UNUserNotificationCenterDelegate,
  @unchecked Sendable
{
  public static let categoryIdentifier = "HANKEY_NEVER_RULE_REVIEW"
  public static let acceptActionIdentifier = "HANKEY_NEVER_RULE_ACCEPT"
  public static let rejectActionIdentifier = "HANKEY_NEVER_RULE_REJECT"
  public static let ruleIDKey = "ruleID"

  public typealias Handler = @MainActor @Sendable (UUID, NeverRuleReviewDecision) -> Void

  private let center: UNUserNotificationCenter
  private let handler: Handler

  public init(
    center: UNUserNotificationCenter = .current(),
    handler: @escaping Handler
  ) {
    self.center = center
    self.handler = handler
    super.init()
  }

  public func start() {
    center.delegate = self
    let accept = UNNotificationAction(
      identifier: Self.acceptActionIdentifier,
      title: "수락",
      options: []
    )
    let reject = UNNotificationAction(
      identifier: Self.rejectActionIdentifier,
      title: "거부하고 항상 변환",
      options: []
    )
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.categoryIdentifier,
        actions: [accept, reject],
        intentIdentifiers: [],
        options: []
      )
    ])
  }

  public func notify(ruleID: UUID) {
    center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
      guard granted, let self else { return }
      let request = UNNotificationRequest(
        identifier: "never-rule-review-\(ruleID.uuidString)",
        content: Self.makeContent(ruleID: ruleID),
        trigger: nil
      )
      self.center.add(request)
    }
  }

  public static func makeContent(ruleID: UUID) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "변환 제외를 유지할까요?"
    content.body = "방금 추가된 로컬 규칙을 검토하세요. 실제 입력 내용은 알림에 포함하지 않았습니다."
    content.sound = .default
    content.categoryIdentifier = categoryIdentifier
    content.userInfo = [ruleIDKey: ruleID.uuidString]
    return content
  }

  public static func decision(for actionIdentifier: String) -> NeverRuleReviewDecision? {
    switch actionIdentifier {
    case acceptActionIdentifier: .accept
    case rejectActionIdentifier: .rejectAndAlwaysConvert
    default: nil
    }
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }
    guard
      let decision = Self.decision(for: response.actionIdentifier),
      let value = response.notification.request.content.userInfo[Self.ruleIDKey] as? String,
      let ruleID = UUID(uuidString: value)
    else { return }
    Task { @MainActor [handler] in
      handler(ruleID, decision)
    }
  }
}
