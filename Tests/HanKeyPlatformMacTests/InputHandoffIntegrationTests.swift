import AppKit
import ApplicationServices
import Carbon.HIToolbox
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

  @MainActor
  func testSyntheticEventsProgressWhilePhysicalPrefixIsWaiting() async throws {
    try await probe(.synthetic)
  }

  @MainActor
  func testStoppedTapReleasesUnpostedEventsOnceAndRejectsNewHandoffs() async throws {
    try await probe(.stopped)
  }

  @MainActor
  func testLostControlWakeRetriesWithoutRepeatingUserEvents() async throws {
    try await probe(.lostWake)
  }

  @MainActor
  func testNativeChordCleanupPrecedesQueuedInput() async throws { try await probe(.native) }
  @MainActor
  func testExpiryCleansNativeModifierBeforeReleasingInput() async throws {
    try await probe(.nativeExpired)
  }
  @MainActor
  func testCancellationCleansNativeModifierBeforeReleasingInput() async throws {
    try await probe(.nativeCancelled)
  }
  @MainActor
  func testOverflowCleansNativeModifierBeforeReleasingInput() async throws {
    try await probe(.nativeOverflow)
  }
  @MainActor
  func testStopCleansNativeModifierBeforeReleasingInput() async throws {
    try await probe(.nativeStopped)
  }

  @MainActor
  func testEmptyQueueExpiryStillCleansNativeModifier() async throws {
    try await probe(.nativeEmptyExpired)
  }
  @MainActor
  func testKnownContextChangeCancelsCommandWaitingForWake() async throws {
    try await probe(.contextChanged)
  }

  private enum Mode {
    case completed, expired, idle, synthetic, stopped, lostWake
    case native, nativeExpired, nativeCancelled, nativeOverflow, nativeStopped, nativeEmptyExpired,
      contextChanged
    var usesNative: Bool {
      switch self {
      case .native, .nativeExpired, .nativeCancelled, .nativeOverflow, .nativeStopped,
        .nativeEmptyExpired, .contextChanged:
        true
      default: false
      }
    }
  }

  @MainActor
  private func probe(_ mode: Mode) async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
      throw XCTSkip("Real event-tap test requires existing Accessibility permission")
    }
    let received = expectation(description: "All test events consumed by downstream tap")
    let rawCount = mode == .nativeEmptyExpired ? 0 : (mode == .nativeOverflow ? 17 : 16)
    let startsNative = mode.usesNative && mode != .contextChanged
    let nativeCount = startsNative ? 4 : (mode == .synthetic ? 2 : 0)
    let sink = HandoffEventSink(expectedCount: rawCount + nativeCount, received: received)
    try sink.start()
    defer { sink.stop() }
    let wakeRoute = HandoffWakeRoute(dropFirst: mode == .lostWake, paused: mode == .contextChanged)
    let gate = InputHandoffGate(
      targetPID: getpid(), wakePoster: { wakeRoute.post($0) },
      sourceReleaseDelay: mode.usesNative && mode != .native
        ? .milliseconds(400) : .milliseconds(20),
      maximumBufferCount: mode == .nativeOverflow ? 16 : 256)
    defer { gate.stop() }
    let rawEvents = try (0..<rawCount).map { ordinal in
      let event = try XCTUnwrap(
        CGEvent(
          keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 0xFFFF,
          keyDown: ordinal.isMultiple(of: 2)))
      event.setIntegerValueField(
        .eventSourceUserData, value: HandoffEventSink.marker + Int64(ordinal))
      event.flags = ordinal.isMultiple(of: 3) ? .maskShift : []
      return event
    }
    let native = mode.usesNative ? try XCTUnwrap(NativeInputSourceSwitch()) : nil
    let syntheticEvents = try [true, false].map { down in
      let event = try XCTUnwrap(
        CGEvent(
          keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 0xFFFE,
          keyDown: down))
      HanKeySyntheticEvent.mark(event)
      event.flags = []
      return event
    }
    let handoff = try XCTUnwrap(InputHandoff(gate: gate))
    defer { handoff.finish() }
    if mode == .idle { handoff.finish() }
    // Prepare before the deadline, then post only to our consuming process tap.
    for event in rawEvents.prefix(16) { event.postToPid(getpid()) }
    if mode != .idle, rawCount > 0 {
      let buffered = await waitForCondition { gate.pendingEventCount == min(rawCount, 16) }
      XCTAssertTrue(buffered, "The physical prefix must reach the gate before the next step")
    }
    switch mode {
    case .completed, .lostWake:
      XCTAssertTrue(handoff.isValid)
      XCTAssertTrue(sink.events.isEmpty, "Input must wait before the downstream tap")
      handoff.finish()
    case .expired:
      XCTAssertTrue(sink.events.isEmpty)
      // Keep main blocked, but allow the hosted OS to schedule its event delivery.
      XCTAssertEqual(sink.waitForAllEvents(timeout: .now() + 2), .success)
      XCTAssertFalse(handoff.isValid)
      XCTAssertEqual(
        sink.events, Array(0..<16), "Deadline must release events without the main loop")
    case .idle:
      XCTAssertEqual(sink.waitForAllEvents(timeout: .now() + 2), .success)
      XCTAssertEqual(sink.events, Array(0..<16), "Idle input must not wait for the main loop")
    case .synthetic:
      for event in syntheticEvents { event.postToPid(getpid()) }
      let progressed = await waitForCondition { sink.events.count == 2 }
      XCTAssertTrue(progressed)
      XCTAssertTrue(handoff.isValid)
      XCTAssertEqual(sink.events, [16, 17], "Synthetic events must progress before input release")
      handoff.finish()
    case .stopped:
      XCTAssertTrue(sink.events.isEmpty)
      gate.stop()
      XCTAssertNil(InputHandoff(gate: gate))
      handoff.finish()
    case .native, .nativeExpired, .nativeCancelled, .nativeOverflow, .nativeStopped,
      .nativeEmptyExpired, .contextChanged:
      let native = try XCTUnwrap(native)
      let commandStarted = ContinuousClock.now
      let command = Task { await handoff.performSourceSwitch(events: native.events) }
      if mode == .contextChanged {
        let queued = await waitForCondition { wakeRoute.count > 0 }
        XCTAssertTrue(queued)
        XCTAssertTrue(handoff.isValid)
        gate.invalidateContext(.applicationChanged)
        wakeRoute.resume()
      } else if mode != .native {
        let started = await waitForCondition { sink.events.count >= 3 }
        XCTAssertTrue(started)
        XCTAssertEqual(sink.events, [1000, 1001, 1002])
      }
      // Normal cleanup may already finish before main resumes; exact order is checked below.
      switch mode {
      case .nativeCancelled: command.cancel()
      case .nativeStopped: gate.stop()
      case .nativeOverflow:
        rawEvents[16].postToPid(getpid())
      default: break
      }
      let switched = await command.value
      XCTAssertEqual(switched, mode == .native)
      if mode == .native {
        XCTAssertGreaterThanOrEqual(commandStarted.duration(to: .now), .milliseconds(20))
        gate.invalidateContext(.inputSourceChanged)
        XCTAssertTrue(handoff.isValid, "Our own source notification must retain the input wait")
      }
      handoff.finish()
      if mode == .nativeEmptyExpired {
        let next = InputHandoff(gate: gate)
        XCTAssertNotNil(next)
        next?.finish()
      }
    }
    await fulfillment(of: [received], timeout: 2)
    // Let duplicate or stale wakes arrive before checking exact multiplicity.
    holdMainRunloop(0.01)
    let syntheticPrefix: [UInt32] =
      startsNative ? [1000, 1001, 1002, 1003] : (mode == .synthetic ? [16, 17] : [])
    XCTAssertEqual(sink.events, syntheticPrefix + (0..<rawCount).map(UInt32.init))
    let syntheticFlags: [UInt64] =
      startsNative
      ? [
        CGEventFlags.maskControl.rawValue, CGEventFlags.maskControl.rawValue,
        CGEventFlags.maskControl.rawValue, 0,
      ]
      : (mode == .synthetic ? [0, 0] : [])
    XCTAssertEqual(
      sink.flags,
      syntheticFlags
        + (0..<rawCount).map { $0.isMultiple(of: 3) ? CGEventFlags.maskShift.rawValue : 0 })
    if mode == .lostWake { XCTAssertGreaterThanOrEqual(wakeRoute.count, 2) }
  }
}

@MainActor
private func waitForCondition(_ condition: () -> Bool) async -> Bool {
  let deadline = ContinuousClock.now + .milliseconds(100)
  while !condition() {
    guard ContinuousClock.now < deadline else { return false }
    try? await Task.sleep(for: .milliseconds(1))
  }
  return true
}

private func holdMainRunloop(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

private final class HandoffEventSink: @unchecked Sendable {
  static let marker: Int64 = 0x48_41_4E_51_41
  private let lock = NSLock()
  private let ready = DispatchSemaphore(value: 0)
  private let stopped = DispatchSemaphore(value: 0)
  private let expectedCount: Int
  private let received: XCTestExpectation
  private let allEventsReceived = DispatchSemaphore(value: 0)
  private var captured: [UInt32] = []
  private var capturedFlags: [UInt64] = []
  private var runLoop: CFRunLoop?
  private var available = false

  init(expectedCount: Int, received: XCTestExpectation) {
    self.expectedCount = expectedCount
    self.received = received
  }

  var events: [UInt32] { lock.withLock { captured } }
  var flags: [UInt64] { lock.withLock { capturedFlags } }

  func waitForAllEvents(timeout: DispatchTime) -> DispatchTimeoutResult {
    allEventsReceived.wait(timeout: timeout)
  }

  func start() throws {
    Thread { [self] in
      defer { stopped.signal() }
      let mask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
      guard
        let tap = CGEvent.tapCreateForPid(
          pid: getpid(), place: .tailAppendEventTap, options: .defaultTap,
          eventsOfInterest: mask,
          callback: { _, type, event, context in
            let marker = event.getIntegerValueField(.eventSourceUserData)
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let isSynthetic = marker == HanKeySyntheticEvent.marker && key == 0xFFFE
            let isNative =
              marker == HanKeySyntheticEvent.marker
              && [Int64(kVK_Control), Int64(kVK_Space)].contains(key)
            let ordinal: Int64
            if isNative {
              ordinal =
                key == Int64(kVK_Control)
                ? (event.flags.isEmpty ? 1003 : 1000) : (type == .keyDown ? 1001 : 1002)
            } else if isSynthetic {
              ordinal = type == .keyDown ? 16 : 17
            } else {
              ordinal = marker - HandoffEventSink.marker
            }
            guard (0..<17).contains(ordinal) || isSynthetic || isNative, let context else {
              return Unmanaged.passUnretained(event)
            }
            let sink = Unmanaged<HandoffEventSink>.fromOpaque(context).takeUnretainedValue()
            let done = sink.lock.withLock {
              sink.captured.append(UInt32(ordinal))
              sink.capturedFlags.append(event.flags.rawValue)
              return sink.captured.count == sink.expectedCount
            }
            if done {
              sink.allEventsReceived.signal()
              sink.received.fulfill()
            }
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

private final class HandoffWakeRoute: @unchecked Sendable {
  private let lock = NSLock()
  private var posted = 0
  private let dropFirst: Bool
  private var paused: Bool
  init(dropFirst: Bool, paused: Bool = false) {
    self.dropFirst = dropFirst
    self.paused = paused
  }
  func resume() { lock.withLock { paused = false } }
  var count: Int { lock.withLock { posted } }
  func post(_ event: CGEvent) {
    let drop = lock.withLock {
      posted += 1
      return paused || (dropFirst && posted == 1)
    }
    if !drop { event.postToPid(getpid()) }
  }
}
