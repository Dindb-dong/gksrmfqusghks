import ApplicationServices
import CoreGraphics
import Foundation
import XCTest

@testable import HanKeyPlatformMac

final class InputHandoffIntegrationTests: XCTestCase {
  @MainActor
  func testPendingEventsLeaveHandoffExactlyOnceAndInOrder() async throws {
    try await probe(.completed)
  }

  @MainActor
  func testExpiredHandoffReleasesEveryEventWhileMainThreadRemainsBlocked() async throws {
    try await probe(.expired)
  }

  @MainActor
  func testIdleTapDoesNotWaitForTheMainThread() async throws {
    try await probe(.idle)
  }

  private enum Mode { case completed, expired, idle }

  @MainActor
  private func probe(_ mode: Mode) async throws {
    guard ProcessInfo.processInfo.environment["HANKEY_RUN_INPUT_HANDOFF_INTEGRATION"] == "1" else {
      throw XCTSkip("Opt-in real event-tap test; no app text is typed")
    }
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
      throw XCTSkip("Real event-tap test requires existing Accessibility permission")
    }
    let received = expectation(description: "All test events consumed by downstream tap")
    let sink = HandoffEventSink(expectedCount: 16, received: received)
    try sink.start()
    defer { sink.stop() }
    holdMainRunloop(0.002)
    let handoff = try XCTUnwrap(InputHandoff())
    defer { handoff.finish() }
    if mode == .idle { handoff.finish() }
    let posted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      for ordinal in 0..<16 {
        // Unmapped key + consuming tap: never type into the user's focused app.
        guard
          let event = CGEvent(
            keyboardEventSource: nil, virtualKey: 0xFFFF, keyDown: ordinal.isMultiple(of: 2))
        else { continue }
        event.setIntegerValueField(
          .eventSourceUserData, value: HandoffEventSink.marker + Int64(ordinal))
        event.post(tap: .cgSessionEventTap)
      }
      posted.signal()
    }
    XCTAssertEqual(posted.wait(timeout: .now() + 0.02), .success)
    switch mode {
    case .completed:
      holdMainRunloop(0.01)
      XCTAssertTrue(handoff.isValid)
      XCTAssertTrue(sink.events.isEmpty, "Input must wait before the downstream tap")
      handoff.finish()
    case .expired:
      holdMainRunloop(0.12)
      XCTAssertFalse(handoff.isValid)
      XCTAssertEqual(
        sink.events, Array(0..<16), "Deadline must release events without the main loop")
    case .idle:
      holdMainRunloop(0.03)
      XCTAssertEqual(sink.events, Array(0..<16), "Idle input must not wait for the main loop")
    }
    await fulfillment(of: [received], timeout: 2)
    XCTAssertEqual(sink.events, Array(0..<16))
  }
}

private func holdMainRunloop(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

private final class HandoffEventSink: @unchecked Sendable {
  static let marker: Int64 = 0x48_41_4E_51_41
  private let lock = NSLock()
  private let ready = DispatchSemaphore(value: 0)
  private let stopped = DispatchSemaphore(value: 0)
  private let expectedCount: Int
  private let received: XCTestExpectation
  private var captured: [UInt32] = []
  private var runLoop: CFRunLoop?
  private var available = false

  init(expectedCount: Int, received: XCTestExpectation) {
    self.expectedCount = expectedCount
    self.received = received
  }

  var events: [UInt32] { lock.withLock { captured } }

  func start() throws {
    Thread { [self] in
      defer { stopped.signal() }
      let mask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
          eventsOfInterest: mask,
          callback: { _, type, event, context in
            let ordinal = event.getIntegerValueField(.eventSourceUserData) - HandoffEventSink.marker
            guard (0..<16).contains(ordinal), let context else {
              return Unmanaged.passUnretained(event)
            }
            let sink = Unmanaged<HandoffEventSink>.fromOpaque(context).takeUnretainedValue()
            let done = sink.lock.withLock {
              sink.captured.append(UInt32(ordinal))
              return sink.captured.count == sink.expectedCount
            }
            if done { sink.received.fulfill() }
            return nil
          }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
      else {
        ready.signal()
        return
      }
      let loop = CFRunLoopGetCurrent()!
      CFRunLoopAddSource(loop, source, .commonModes)
      lock.withLock {
        runLoop = loop
        available = true
      }
      ready.signal()
      CFRunLoopRun()
      CGEvent.tapEnable(tap: tap, enable: false)
      CFRunLoopRemoveSource(loop, source, .commonModes)
      CFMachPortInvalidate(tap)
    }.start()
    guard ready.wait(timeout: .now() + 1) == .success, lock.withLock({ available }) else {
      throw XCTSkip("Could not establish consuming event tap; no events posted")
    }
  }

  func stop() {
    if let loop = lock.withLock({ runLoop }) {
      CFRunLoopStop(loop)
      _ = stopped.wait(timeout: .now() + 1)
    }
  }
}
