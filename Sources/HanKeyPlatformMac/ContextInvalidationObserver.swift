import AppKit
import HanKeyCore

public final class ContextInvalidationObserver: @unchecked Sendable {
  public typealias Handler = @Sendable (BufferInvalidationReason) -> Void

  private let handler: Handler
  private var workspaceToken: NSObjectProtocol?
  private var inputSourceToken: NSObjectProtocol?

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  deinit {
    stop()
  }

  public func start() {
    guard workspaceToken == nil, inputSourceToken == nil else {
      return
    }

    workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [handler] _ in
      handler(.applicationChanged)
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
    if let workspaceToken {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
    }
    if let inputSourceToken {
      NotificationCenter.default.removeObserver(inputSourceToken)
    }
    workspaceToken = nil
    inputSourceToken = nil
  }
}
