import Foundation
@preconcurrency import UserNotifications

public enum NeverRuleReviewDecision: Equatable, Sendable {
  case keepExcluded
  case alwaysConvert
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
    center.setNotificationCategories([Self.makeCategory()])
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
    content.title = "이 입력을 앞으로 어떻게 처리할까요?"
    content.body = "교정 결과를 지운 뒤 같은 입력을 다시 쳤습니다. 원하는 동작을 선택하세요. 입력 내용은 표시하지 않습니다."
    content.sound = .default
    content.categoryIdentifier = categoryIdentifier
    content.userInfo = [ruleIDKey: ruleID.uuidString]
    return content
  }

  public static func makeCategory() -> UNNotificationCategory {
    let keepExcluded = UNNotificationAction(
      identifier: acceptActionIdentifier,
      title: "변환하지 않기",
      options: []
    )
    let alwaysConvert = UNNotificationAction(
      identifier: rejectActionIdentifier,
      title: "계속 자동 변환",
      options: []
    )
    return UNNotificationCategory(
      identifier: categoryIdentifier,
      actions: [keepExcluded, alwaysConvert],
      intentIdentifiers: [],
      options: []
    )
  }

  public static func decision(for actionIdentifier: String) -> NeverRuleReviewDecision? {
    switch actionIdentifier {
    case acceptActionIdentifier: .keepExcluded
    case rejectActionIdentifier: .alwaysConvert
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
