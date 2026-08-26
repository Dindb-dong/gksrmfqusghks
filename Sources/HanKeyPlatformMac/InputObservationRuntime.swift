import Carbon.HIToolbox
import Foundation
import HanKeyCore

public enum InputObservationState: String, Equatable, Sendable {
  case stopped
  case observing
  case protected
  case permissionRequired
  case tapUnavailable
}

public enum InputObservationRuntimeEvent: Equatable, Sendable {
  case stateChanged(InputObservationState)
  case wordCompleted(
    BufferedWord,
    boundary: WordBoundary,
    focusIdentity: FocusedElementIdentity
  )
}

@MainActor
public final class InputObservationRuntime {
  public typealias Handler = @MainActor @Sendable (InputObservationRuntimeEvent) -> Void

  private let handler: Handler
  private var buffer: WordBuffer
  private var state: InputObservationState = .stopped
  private var focusTracker = FocusIdentityTracker()
  private var currentFocusIdentity: FocusedElementIdentity?
  private lazy var eventTap = GlobalInputEventTap { [weak self] observation in
    MainActor.assumeIsolated {
      self?.receive(observation)
    }
  }
  private lazy var contextObserver = ContextInvalidationObserver { [weak self] reason in
    Task { @MainActor [weak self] in
      self?.invalidate(reason)
    }
  }

  public init(
    buffer: WordBuffer = WordBuffer(),
    handler: @escaping Handler
  ) {
    self.buffer = buffer
    self.handler = handler
  }

  @discardableResult
  public func start() -> Bool {
    let permissions = PlatformCapabilities.currentPermissionSnapshot()
    guard permissions.hasRequiredPermissions else {
      transition(to: .permissionRequired)
      return false
    }

    contextObserver.start()
    guard eventTap.start() else {
      contextObserver.stop()
      transition(to: .tapUnavailable)
      return false
    }

    refreshProtection(at: currentTimestamp())
    if state != .protected {
      transition(to: .observing)
    }
    return true
  }

  public func stop() {
    eventTap.stop()
    contextObserver.stop()
    _ = buffer.handle(.invalidate(.stopped), at: currentTimestamp())
    focusTracker.reset()
    currentFocusIdentity = nil
    transition(to: .stopped)
  }

  private func receive(_ observation: GlobalInputObservation) {
    let timestamp: UInt64
    switch observation {
    case .tapRecovered:
      timestamp = currentTimestamp()
      _ = buffer.handle(.invalidate(.unknownKey), at: timestamp)
    case .buffer(_, let eventTimestamp):
      timestamp = eventTimestamp
    }

    guard refreshProtection(at: timestamp) else {
      return
    }

    switch observation {
    case .tapRecovered:
      transition(to: .observing)
    case .buffer(let bufferObservation, _):
      let action = buffer.handle(bufferObservation, at: timestamp)
      if case .completed(let word, let boundary) = action, let currentFocusIdentity {
        handler(
          .wordCompleted(
            word,
            boundary: boundary,
            focusIdentity: currentFocusIdentity
          )
        )
      }
    }
  }

  private func invalidate(_ reason: BufferInvalidationReason) {
    let timestamp = currentTimestamp()
    guard refreshProtection(at: timestamp) else {
      return
    }
    _ = buffer.handle(.invalidate(reason), at: timestamp)
  }

  @discardableResult
  private func refreshProtection(at timestamp: UInt64) -> Bool {
    let permissions = PlatformCapabilities.currentPermissionSnapshot()
    guard permissions.hasRequiredPermissions else {
      _ = buffer.handle(.invalidate(.focusChanged), at: timestamp)
      focusTracker.reset()
      currentFocusIdentity = nil
      transition(to: .permissionRequired)
      return false
    }
    let secureInput = permissions.isSecureInputEnabled
    let focusedContext = FocusedElementSecurityInspector.currentContext()
    let mustProtect =
      secureInput || focusedContext.state == .secure || focusedContext.surface != .standardText

    if mustProtect {
      _ = buffer.handle(.protectionChanged(isProtected: true), at: timestamp)
      focusTracker.reset()
      currentFocusIdentity = nil
      transition(to: .protected)
      return false
    }

    if buffer.isProtected {
      _ = buffer.handle(.protectionChanged(isProtected: false), at: timestamp)
    }
    guard focusedContext.state == .editable, let identity = focusedContext.identity else {
      _ = buffer.handle(.invalidate(.focusChanged), at: timestamp)
      focusTracker.reset()
      currentFocusIdentity = nil
      transition(to: .observing)
      return false
    }
    if focusTracker.update(identity) {
      _ = buffer.handle(.invalidate(.focusChanged), at: timestamp)
    }
    currentFocusIdentity = identity
    transition(to: .observing)
    return true
  }

  private func transition(to newState: InputObservationState) {
    guard state != newState else {
      return
    }
    state = newState
    handler(.stateChanged(newState))
  }

  private func currentTimestamp() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
  }
}
