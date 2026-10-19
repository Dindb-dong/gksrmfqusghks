import Foundation

/// Scalar status only: no text, events, app identity, timestamps, history, or persistence.
public enum InputHandoffDiagnostics {
  public enum Stage: Int, Sendable {
    case prepared, gateBegan, textPosted, textVerified, nativeQueued, nativeStarted
    case nativeReleased, sourceAcknowledged, finalVerified
  }
  public enum Outcome: String, Sendable {
    case pending, completed, cancelled, budgetBeforeNative, contextCancelled, nativeDispatchFailed
    case sourceUnacknowledged, replacementUnverified, replacementRejected
  }
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var stage = Stage.prepared
    var outcome = Outcome.pending
  }
  private static let state = State()
  @MainActor private static var requestObserver: NSObjectProtocol?

  static func begin() {
    state.lock.withLock {
      state.stage = .prepared
      state.outcome = .pending
    }
  }
  static func reached(_ stage: Stage) {
    state.lock.withLock {
      if stage.rawValue > state.stage.rawValue { state.stage = stage }
    }
  }
  static func ended(_ outcome: Outcome) { state.lock.withLock { state.outcome = outcome } }
  static func endIfPending(_ outcome: Outcome) {
    state.lock.withLock { if state.outcome == .pending { state.outcome = outcome } }
  }
  static var snapshot: (stage: Stage, outcome: Outcome) {
    state.lock.withLock { (state.stage, state.outcome) }
  }

  @MainActor public static func startLocalTestResponder() {
    guard requestObserver == nil,
      Bundle.main.object(forInfoDictionaryKey: "HanKeyBuildChannel") as? String == "local-test"
    else { return }
    let center = DistributedNotificationCenter.default()
    requestObserver = center.addObserver(
      forName: Notification.Name("com.dindbdong.hankey.handoff-status.request"),
      object: nil, queue: .main
    ) { notification in
      guard let requestID = notification.object as? String, UUID(uuidString: requestID) != nil
      else { return }
      let status = snapshot
      center.postNotificationName(
        Notification.Name("com.dindbdong.hankey.handoff-status.response"), object: requestID,
        userInfo: ["stage": String(describing: status.stage), "outcome": status.outcome.rawValue],
        deliverImmediately: true)
    }
  }
}
