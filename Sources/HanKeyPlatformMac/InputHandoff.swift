import CoreGraphics
import Foundation
import HanKeyCore

@MainActor
public protocol InputHandoffControlling: AnyObject {
  var isValid: Bool { get }
  var canStartSourceSwitch: Bool { get }
  func finish()
  func performSourceSwitch(events: [CGEvent]) async -> Bool
}

extension InputHandoffControlling {
  public var canStartSourceSwitch: Bool { isValid }
  public func performSourceSwitch(events: [CGEvent]) async -> Bool { false }
}

@MainActor
public final class InputHandoff: InputHandoffControlling {
  private let token: UInt64
  private let gate: InputHandoffGate

  public convenience init?() { self.init(gate: InputHandoffGateStore.shared.getOrCreate()) }

  init?(gate: InputHandoffGate) {
    guard let token = gate.begin() else { return nil }
    self.gate = gate
    self.token = token
  }

  nonisolated static func shouldWait(for event: CGEvent) -> Bool {
    !HanKeySyntheticEvent.isMarked(event)
  }

  public var isValid: Bool { gate.isValid(token) }
  public var canStartSourceSwitch: Bool { gate.isValid(token, reserve: 35_000_000) }
  public func finish() { gate.finish(token) }
  nonisolated public static func shutdown() { InputHandoffGateStore.shared.shutdown() }
  nonisolated public static func cancelActive(for reason: BufferInvalidationReason) {
    InputHandoffGateStore.shared.cancelActive(for: reason)
  }
  public func performSourceSwitch(events: [CGEvent]) async -> Bool {
    guard !Task.isCancelled else { return false }
    return await withTaskCancellationHandler {
      await gate.performSourceSwitch(token, events: events)
    } onCancel: { [gate, token] in
      gate.finish(token)
    }
  }
}

// Stopping observation before permission is granted must not create a failed global tap.
final class InputHandoffGateStore: @unchecked Sendable {
  static let shared = InputHandoffGateStore()
  private let lock = NSLock()
  private var existing: InputHandoffGate?
  private let makeGate: () -> InputHandoffGate

  init(makeGate: @escaping () -> InputHandoffGate = { InputHandoffGate() }) {
    self.makeGate = makeGate
  }

  func getOrCreate() -> InputHandoffGate {
    lock.withLock {
      if let existing { return existing }
      let gate = makeGate()
      existing = gate
      return gate
    }
  }

  func cancelActive(for reason: BufferInvalidationReason) {
    lock.withLock { existing }?.invalidateContext(reason)
  }

  func shutdown() { lock.withLock { existing }?.stop() }
}

// The callback returns immediately so native input-source shortcuts can still run.
// User events exist only in this bounded, volatile queue and are never logged or persisted.
final class InputHandoffGate: @unchecked Sendable {
  private let lock = NSLock()
  private let ready = DispatchSemaphore(value: 0)
  private let stopped = DispatchSemaphore(value: 0)
  private let deadlineQueue = DispatchQueue(label: "HanKey.InputHandoffDeadline")
  private var buffer: InputHandoffBuffer<CGEvent>
  private var tap: CFMachPort?
  private var loop: CFRunLoop?
  private var available = false
  private let targetPID: pid_t?
  private let wake: CGEvent?
  private let wakePoster: (@Sendable (CGEvent) -> Void)?
  private var wakeRetryToken: UInt64?
  private let sourceReleaseDelay: DispatchTimeInterval
  private struct SourceCommand {
    let token: UInt64
    let events: [CGEvent]
    let completion: CheckedContinuation<Bool, Never>
    var started = false
    var cleanupRequested = false
    var cancelled = false
  }
  private var sourceCommand: SourceCommand?
  private var activeToken: UInt64 = 0
  private var sourceWasStarted = false

  // The PID seam lets integration tests exercise this implementation without a global tap.
  init(
    targetPID: pid_t? = nil, wakePoster: (@Sendable (CGEvent) -> Void)? = nil,
    sourceReleaseDelay: DispatchTimeInterval = .milliseconds(20), maximumBufferCount: Int = 256
  ) {
    self.targetPID = targetPID
    self.wakePoster = wakePoster
    self.sourceReleaseDelay = sourceReleaseDelay
    buffer = InputHandoffBuffer(maximumCount: maximumBufferCount)
    wake = CGEvent(
      keyboardEventSource: CGEventSource(stateID: .privateState),
      virtualKey: 0xFFFF, keyDown: false)
    if let wake { HanKeySyntheticEvent.mark(wake) }
    guard wake != nil else { return }
    Thread { [self] in
      defer { stopped.signal() }
      let types: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
      ]
      let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
      let callback: CGEventTapCallBack = { proxy, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return Unmanaged<InputHandoffGate>.fromOpaque(context).takeUnretainedValue()
          .receive(proxy: proxy, type: type, event: event)
      }
      let context = Unmanaged.passUnretained(self).toOpaque()
      let port: CFMachPort?
      if let targetPID {
        port = CGEvent.tapCreateForPid(
          pid: targetPID, place: .headInsertEventTap, options: .defaultTap,
          eventsOfInterest: mask, callback: callback, userInfo: context)
      } else {
        port = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
          eventsOfInterest: mask, callback: callback, userInfo: context)
      }
      guard let port,
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
      else {
        ready.signal()
        return
      }
      let runLoop = CFRunLoopGetCurrent()!
      CFRunLoopAddSource(runLoop, source, .commonModes)
      lock.withLock {
        tap = port
        loop = runLoop
        available = true
      }
      ready.signal()
      CFRunLoopRun()
      CGEvent.tapEnable(tap: port, enable: false)
      CFRunLoopRemoveSource(runLoop, source, .commonModes)
      CFMachPortInvalidate(port)
    }.start()
    _ = ready.wait(timeout: .now() + 1)
  }

  var pendingEventCount: Int { lock.withLock { buffer.count } }

  func begin() -> UInt64? {
    lock.lock()
    defer { lock.unlock() }
    guard available, sourceCommand == nil, let tap, CGEvent.tapIsEnabled(tap: tap),
      let token = buffer.begin(now: DispatchTime.now().uptimeNanoseconds)
    else { return nil }
    activeToken = token
    sourceWasStarted = false
    deadlineQueue.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
      self?.expire(token)
    }
    return token
  }

  func isValid(_ token: UInt64, reserve: UInt64 = 15_000_000) -> Bool {
    lock.withLock {
      available && tap.map { CGEvent.tapIsEnabled(tap: $0) } == true
        && buffer.isValid(token, now: DispatchTime.now().uptimeNanoseconds, reserve: reserve)
    }
  }

  func invalidateContext(_ reason: BufferInvalidationReason) {
    let token = lock.withLock { () -> UInt64? in
      // Our own native switch is an expected source change, not a focus change.
      if reason == .inputSourceChanged, sourceWasStarted { return nil }
      return activeToken
    }
    if let token { finish(token) }
  }

  func finish(_ token: UInt64) {
    lock.withLock {
      if releaseIfDisabled() { return }
      let needsDrain = buffer.requestRelease(token)
      let hasCommand = sourceCommand?.token == token
      if hasCommand {
        sourceCommand?.cancelled = true
        sourceCommand?.cleanupRequested = true
      }
      if needsDrain || hasCommand { requestWake(token) }
    }
  }

  private func expire(_ token: UInt64) {
    lock.withLock {
      if releaseIfDisabled() { return }
      let now = DispatchTime.now().uptimeNanoseconds
      let needsDrain = buffer.expire(token, now: now)
      let hasExpiredCommand =
        sourceCommand?.token == token && !buffer.isValid(token, now: now, reserve: 0)
      if hasExpiredCommand {
        sourceCommand?.cancelled = true
        sourceCommand?.cleanupRequested = true
      }
      if needsDrain || hasExpiredCommand { requestWake(token) }
    }
  }

  @MainActor
  func performSourceSwitch(_ token: UInt64, events: [CGEvent]) async -> Bool {
    await withCheckedContinuation { completion in
      lock.withLock {
        guard available, sourceCommand == nil, events.count == 4,
          buffer.isValid(token, now: DispatchTime.now().uptimeNanoseconds, reserve: 35_000_000)
        else {
          completion.resume(returning: false)
          return
        }
        sourceCommand = SourceCommand(token: token, events: events, completion: completion)
        requestWake(token)
      }
    }
  }

  // All chord events and physical prefixes leave from this callback, in the same order.
  private func serviceSourceCommand(proxy: CGEventTapProxy, forceRelease: Bool, now: UInt64) {
    guard var command = sourceCommand else { return }
    let mustRelease = forceRelease || command.cancelled
    if !command.started {
      guard !mustRelease, buffer.isValid(command.token, now: now, reserve: 35_000_000) else {
        sourceCommand = nil
        command.completion.resume(returning: false)
        return
      }
      command.started = true
      sourceWasStarted = true
      sourceCommand = command
      for event in command.events.dropLast() { event.tapPostEvent(proxy) }
      let token = command.token
      deadlineQueue.asyncAfter(deadline: .now() + sourceReleaseDelay) { [weak self] in
        guard let self else { return }
        self.lock.withLock {
          guard self.sourceCommand?.token == token else { return }
          self.sourceCommand?.cleanupRequested = true
          self.requestWake(token)
        }
      }
    }
    guard mustRelease || command.cleanupRequested else { return }
    sourceCommand = nil
    command.events[3].tapPostEvent(proxy)
    command.completion.resume(returning: !mustRelease)
  }

  private func needsWake(_ token: UInt64) -> Bool {
    if let command = sourceCommand, command.token == token,
      !command.started || command.cleanupRequested
    {
      return true
    }
    return buffer.expire(token, now: DispatchTime.now().uptimeNanoseconds)
  }

  private func requestWake(_ token: UInt64) {
    guard wakeRetryToken != token else { return }
    wakeRetryToken = token
    sendWake()
    scheduleWakeRetry(token, remaining: 10)
  }

  private func sendWake() {
    if let wake, let wakePoster { wakePoster(wake) } else { post(wake) }
  }

  private func scheduleWakeRetry(_ token: UInt64, remaining: Int) {
    deadlineQueue.asyncAfter(deadline: .now() + .milliseconds(4)) { [weak self] in
      guard let self else { return }
      self.lock.withLock {
        guard self.wakeRetryToken == token else { return }
        guard !self.releaseIfDisabled(),
          self.needsWake(token)
        else {
          self.wakeRetryToken = nil
          return
        }
        guard remaining > 0 else {
          self.releaseAfterTapFailure()
          return
        }
        // Only the content-free control wake is retried, never a user event.
        self.sendWake()
        self.scheduleWakeRetry(token, remaining: remaining - 1)
      }
    }
  }

  private func receive(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    lock.lock()
    defer { lock.unlock() }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      releaseAfterTapFailure()
      return Unmanaged.passUnretained(event)
    }
    let now = DispatchTime.now().uptimeNanoseconds
    if HanKeySyntheticEvent.isMarked(event), type == .keyUp,
      event.getIntegerValueField(.keyboardEventKeycode) == 0xFFFF
    {
      let mustDrain = buffer.needsDrain(now: now)
      serviceSourceCommand(proxy: proxy, forceRelease: mustDrain, now: now)
      if mustDrain {
        for pending in buffer.drain() { pending.tapPostEvent(proxy) }
      }
      return nil
    }
    guard InputHandoff.shouldWait(for: event) else { return Unmanaged.passUnretained(event) }
    switch buffer.receive(now: now, copy: { event.copy() }) {
    case .buffered:
      serviceSourceCommand(proxy: proxy, forceRelease: false, now: now)
      return nil
    case .pass(let prefix):
      serviceSourceCommand(proxy: proxy, forceRelease: true, now: now)
      // Proxy posts precede this returned event; new callbacks cannot overtake the prefix.
      for pending in prefix { pending.tapPostEvent(proxy) }
      return Unmanaged.passUnretained(event)
    }
  }

  private func post(_ event: CGEvent?) {
    guard let event else { return }
    if let targetPID { event.postToPid(targetPID) } else { event.post(tap: .cgSessionEventTap) }
  }

  private func releaseIfDisabled() -> Bool {
    guard available, tap.map({ CGEvent.tapIsEnabled(tap: $0) }) != true else { return false }
    releaseAfterTapFailure()
    return true
  }

  private func releaseAfterTapFailure() {
    // The OS can already pass newer input after disabling a tap. Release unposted input once,
    // cancel corrections, and require a restart instead of risking duplicate replay on recovery.
    available = false
    wakeRetryToken = nil
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let command = sourceCommand {
      sourceCommand = nil
      if command.started { post(command.events[3]) }
      command.completion.resume(returning: false)
    }
    for pending in buffer.drain() { post(pending) }
  }

  func stop() {
    let runLoop = lock.withLock { () -> CFRunLoop? in
      releaseAfterTapFailure()
      defer { loop = nil }
      return loop
    }
    if let runLoop {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
      _ = stopped.wait(timeout: .now() + 1)
    }
  }
}
