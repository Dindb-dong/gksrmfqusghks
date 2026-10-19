import CoreGraphics
import HanKeyCore

@testable import HanKeyPlatformMac

@MainActor
final class TimedInputHandoff: InputHandoffControlling {
  private var buffer = InputHandoffBuffer<Int>()
  private let token: UInt64
  var now: UInt64 = 0
  var commandCount = 0
  var queueDelayMilliseconds: UInt64 = 0
  var onCommand: (() -> Void)?

  init() { token = buffer.begin(now: 0)! }
  var isValid: Bool { buffer.isValid(token, now: now) }
  var canStartSourceSwitch: Bool { buffer.isValid(token, now: now, reserve: 35_000_000) }
  func advance(milliseconds: UInt64) { now += milliseconds * 1_000_000 }
  func finish() { buffer.requestRelease(token) }
  func performSourceSwitch(events: [CGEvent]) async -> Bool {
    InputHandoffDiagnostics.reached(.nativeQueued)
    advance(milliseconds: queueDelayMilliseconds)
    guard !Task.isCancelled, canStartSourceSwitch else { return false }
    InputHandoffDiagnostics.reached(.nativeStarted)
    commandCount += 1
    advance(milliseconds: 20)
    InputHandoffDiagnostics.reached(.nativeReleased)
    onCommand?()
    return isValid
  }
}
