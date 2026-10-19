import CoreGraphics
import Foundation

@MainActor
public protocol InputHandoffControlling: AnyObject {
  var isValid: Bool { get }
  func finish()
}

/// Only the handoff waits; the independent event-tap thread forwards idle input immediately.
@MainActor
public final class InputHandoff: InputHandoffControlling {
  private let token: UInt64
  private let gate: InputHandoffGate

  public init?() {
    let gate = InputHandoffGate.shared
    guard let token = gate.begin() else { return nil }
    self.gate = gate
    self.token = token
  }

  // Replacement events must reach the target while physical input waits.
  nonisolated static func shouldWait(for event: CGEvent) -> Bool {
    !HanKeySyntheticEvent.isMarked(event)
  }

  public var isValid: Bool { gate.isValid(token) }
  public func finish() { gate.finish(token) }
}

// The condition guards the token/deadline, not user content. Events stay on the OS callback stack.
private final class InputHandoffGate: @unchecked Sendable {
  static let shared = InputHandoffGate()
  private let condition = NSCondition()
  private let ready = DispatchSemaphore(value: 0)
  private var tap: CFMachPort?
  private var token: UInt64 = 0
  private var deadline: ContinuousClock.Instant?

  private init() {
    Thread { [self] in
      let types: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
      ]
      let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
      guard
        let port = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
          eventsOfInterest: mask,
          callback: { _, type, event, context in
            if let context {
              if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
                || InputHandoff.shouldWait(for: event)
              {
                Unmanaged<InputHandoffGate>.fromOpaque(context).takeUnretainedValue()
                  .waitForHandoff(type)
              }
            }
            return Unmanaged.passUnretained(event)
          }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
      else {
        ready.signal()
        return
      }
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      condition.lock()
      tap = port
      condition.unlock()
      ready.signal()
      CFRunLoopRun()
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }.start()
    _ = ready.wait(timeout: .now() + 1)
  }

  func begin() -> UInt64? {
    condition.lock()
    defer { condition.unlock() }
    guard deadline == nil,
      let tap, CGEvent.tapIsEnabled(tap: tap)
    else { return nil }
    token &+= 1
    deadline = .now.advanced(by: .milliseconds(80))
    return token
  }

  func isValid(_ expected: UInt64) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    // Reserve the 10ms AX timeout plus posting margin before starting a mutation.
    return token == expected
      && deadline.map { ContinuousClock.now.advanced(by: .milliseconds(15)) < $0 } == true
      && tap.map { CGEvent.tapIsEnabled(tap: $0) } == true
  }

  func finish(_ expected: UInt64) {
    condition.lock()
    defer { condition.unlock() }
    guard token == expected else { return }
    deadline = nil
    condition.broadcast()
  }

  private func waitForHandoff(_ type: CGEventType) {
    condition.lock()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      token &+= 1
      deadline = nil
      let port = tap
      condition.broadcast()
      condition.unlock()
      if let port { CGEvent.tapEnable(tap: port, enable: true) }
      return
    }
    let eventDeadline = ContinuousClock.now.advanced(by: .milliseconds(80))
    while let activeDeadline = deadline {
      // A new handoff can start before a released callback wakes. Honor it, but cap total wait.
      let remaining = ContinuousClock.now.duration(to: min(activeDeadline, eventDeadline))
      if remaining <= .zero {
        token &+= 1
        deadline = nil
        condition.broadcast()
        break
      }
      let parts = remaining.components
      _ = condition.wait(
        until: Date(
          timeIntervalSinceNow:
            Double(parts.seconds) + Double(parts.attoseconds) / 1e18))
    }
    condition.unlock()
  }
}
