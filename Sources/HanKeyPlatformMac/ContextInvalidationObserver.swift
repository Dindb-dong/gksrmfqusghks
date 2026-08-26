import AppKit
import HanKeyCore

public final class ContextInvalidationObserver: @unchecked Sendable {
  public typealias Handler = @Sendable (BufferInvalidationReason) -> Void

  private let handler: Handler
  private var workspaceTokens: [NSObjectProtocol] = []
  private var inputSourceToken: NSObjectProtocol?

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  deinit {
    stop()
  }

  public func start() {
    guard workspaceTokens.isEmpty, inputSourceToken == nil else {
      return
    }

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceTokens.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
      ) { [handler] _ in
        handler(.applicationChanged)
      })
    let systemNotifications: [Notification.Name] = [
      NSWorkspace.willSleepNotification,
      NSWorkspace.didWakeNotification,
      NSWorkspace.sessionDidResignActiveNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
      NSWorkspace.screensDidSleepNotification,
      NSWorkspace.screensDidWakeNotification,
    ]
    for name in systemNotifications {
      workspaceTokens.append(
        workspaceCenter.addObserver(
          forName: name,
          object: nil,
          queue: .main
        ) { [handler] _ in
          handler(.systemStateChanged)
        })
    }
    inputSourceToken = NotificationCenter.default.addObserver(
      forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
      object: nil,
      queue: .main
    ) { [handler] _ in
      handler(.inputSourceChanged)
    }
  }

  public func stop() {
    for workspaceToken in workspaceTokens {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
    }
    if let inputSourceToken {
      NotificationCenter.default.removeObserver(inputSourceToken)
    }
    workspaceTokens.removeAll()
    inputSourceToken = nil
  }
}
