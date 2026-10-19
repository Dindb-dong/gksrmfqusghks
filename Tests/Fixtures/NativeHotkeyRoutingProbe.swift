import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

// Standalone, explicitly authorized routing probe. Never part of `swift test` or check.sh.
// No input-source selection, text entry, window creation, or application activation.
private final class Probe: @unchecked Sendable {
  // Exact HanKey synthetic tag prevents the running observer from invalidating user buffers.
  static let marker: Int64 = 0x48_41_4E_4B_45_59
  let lock = NSLock()
  let ready = DispatchSemaphore(value: 0)
  private var hits = 0
  private var consumed = 0
  private var tap: CFMachPort?
  private var loop: CFRunLoop?
  private let holdCondition = NSCondition()
  let holdEntered = DispatchSemaphore(value: 0)
  private var holdDeadline: ContinuousClock.Instant?
  private var acknowledgedWhileHeld = false
  private var heldTap: CFMachPort?
  private var proxyMode = false
  private var proxyEvents: [CGEvent] = []

  var hotkeyArrivedWhileHeld: Bool {
    holdCondition.lock()
    defer { holdCondition.unlock() }
    return acknowledgedWhileHeld
  }

  private func holdOwnUnmappedEvent() {
    holdCondition.lock()
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(40))
    holdDeadline = deadline
    holdEntered.signal()
    while holdDeadline != nil {
      let remaining = ContinuousClock.now.duration(to: deadline)
      guard remaining > .zero else { break }
      let parts = remaining.components
      _ = holdCondition.wait(
        until: Date(
          timeIntervalSinceNow:
            Double(parts.seconds) + Double(parts.attoseconds) / 1e18))
    }
    holdDeadline = nil
    holdCondition.unlock()
  }

  var hitCount: Int { lock.withLock { hits } }
  var consumedCount: Int { lock.withLock { consumed } }
  func consume() { lock.withLock { consumed += 1 } }
  var isSinkEnabled: Bool {
    lock.withLock { tap.map { CGEvent.tapIsEnabled(tap: $0) } == true }
  }
  func receiveHotkey() {
    lock.withLock { hits += 1 }
    holdCondition.lock()
    if let deadline = holdDeadline, ContinuousClock.now < deadline {
      acknowledgedWhileHeld = true
      holdDeadline = nil
      holdCondition.broadcast()
    }
    holdCondition.unlock()
  }

  func startSink(withHold: Bool = false, withProxy: Bool = false) -> Bool {
    proxyMode = withProxy
    if withProxy {
      guard let source = CGEventSource(stateID: .privateState) else { return false }
      for down in [true, false] {
        guard
          let event = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(kVK_F20), keyDown: down)
        else { return false }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: Probe.marker)
        proxyEvents.append(event)
      }
    }
    Thread { [self] in
      let callback: CGEventTapCallBack = { _, _, event, context in
        // Consume only known probe events. Other events can queue behind the bounded gate.
        if event.getIntegerValueField(.eventSourceUserData) == Probe.marker,
          [Int64(kVK_F20), 0xFFFF].contains(event.getIntegerValueField(.keyboardEventKeycode))
        {
          if let context {
            Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue().consume()
          }
          return nil
        }
        return Unmanaged.passUnretained(event)
      }
      let mask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
      guard
        let port = CGEvent.tapCreate(
          tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
          eventsOfInterest: mask, callback: callback,
          userInfo: Unmanaged.passUnretained(self).toOpaque()),
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
      else {
        ready.signal()
        return
      }
      lock.withLock {
        tap = port
        loop = CFRunLoopGetCurrent()
      }
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      var gatePort: CFMachPort?
      if withHold || withProxy {
        guard
          let gate = CGEvent.tapCreate(
            tap: withProxy ? .cgSessionEventTap : .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, context in
              guard event.getIntegerValueField(.eventSourceUserData) == Probe.marker,
                event.getIntegerValueField(.keyboardEventKeycode) == 0xFFFF,
                let context
              else { return Unmanaged.passUnretained(event) }
              if type == .keyDown {
                let owner = Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue()
                if owner.proxyMode {
                  for pending in owner.proxyEvents { pending.tapPostEvent(proxy) }
                } else {
                  owner.holdOwnUnmappedEvent()
                }
              }
              return nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
          let gateSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gate, 0)
        else {
          CGEvent.tapEnable(tap: port, enable: false)
          CFMachPortInvalidate(port)
          ready.signal()
          return
        }
        gatePort = gate
        lock.withLock { heldTap = gate }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), gateSource, .commonModes)
      }
      ready.signal()
      CFRunLoopRun()
      if let gatePort {
        CGEvent.tapEnable(tap: gatePort, enable: false)
        CFMachPortInvalidate(gatePort)
      }
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }.start()
    guard ready.wait(timeout: .now() + .seconds(1)) == .success else { return false }
    return lock.withLock {
      tap.map { CGEvent.tapIsEnabled(tap: $0) } == true
        && (!(withHold || withProxy) || heldTap.map { CGEvent.tapIsEnabled(tap: $0) } == true)
    }
  }

  func stopSink() {
    if let runloop = lock.withLock({ loop }) {
      CFRunLoopStop(runloop)
      CFRunLoopWakeUp(runloop)
    }
  }
}

@MainActor
private func pumpHotkeys(for duration: TimeInterval) {
  let deadline = Date(timeIntervalSinceNow: duration)
  var spec = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  while deadline.timeIntervalSinceNow > 0 {
    var event: EventRef?
    let status = ReceiveNextEvent(
      1, &spec, max(0, min(0.005, deadline.timeIntervalSinceNow)), true, &event)
    if status == noErr, let event {
      SendEventToEventTarget(event, GetApplicationEventTarget())
      ReleaseEvent(event)
    }
  }
}

@MainActor
private func run() -> Int32 {
  let arguments = Array(CommandLine.arguments.dropFirst())
  let dispatchOnly = arguments == ["--check-dispatch-only"]
  let handoffProbe = arguments == ["--allow-handoff-routing-test"]
  let proxyProbe = arguments == ["--allow-proxy-routing-test"]
  guard dispatchOnly || handoffProbe || proxyProbe || arguments == ["--allow-session-test-events"]
  else {
    print("Not run: explicit --allow-session-test-events authorization is required")
    return 64
  }
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let initialFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
  let state = Probe()
  let handler: EventHandlerUPP = { _, _, data in
    guard let data else { return OSStatus(eventNotHandledErr) }
    Unmanaged<Probe>.fromOpaque(data).takeUnretainedValue().receiveHotkey()
    return noErr
  }
  var spec = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  var handlerRef: EventHandlerRef?
  guard
    InstallEventHandler(
      GetApplicationEventTarget(), handler, 1, &spec, Unmanaged.passUnretained(state).toOpaque(),
      &handlerRef) == noErr
  else {
    print("SKIP own handler unavailable")
    return 1
  }
  defer { if let handlerRef { RemoveEventHandler(handlerRef) } }

  // Calibrate the exact dispatcher using only this process's Carbon queue.
  var calibration: EventRef?
  guard
    CreateEvent(
      nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(),
      EventAttributes(kEventAttributeNone), &calibration) == noErr,
    let calibration
  else { return 1 }
  let posted = PostEventToQueue(GetCurrentEventQueue(), calibration, Int16(kEventPriorityStandard))
  ReleaseEvent(calibration)
  guard posted == noErr else { return 1 }
  pumpHotkeys(for: 0.02)
  guard state.hitCount == 1 else {
    print("FAIL own-process Carbon dispatcher calibration")
    return 1
  }
  print("own-process Carbon dispatcher calibration passed")
  if dispatchOnly { return 0 }

  defer { state.stopSink() }
  guard state.startSink(withHold: handoffProbe, withProxy: proxyProbe) else {
    print("SKIP consuming sink unavailable")
    return 1
  }

  var hotkey: EventHotKeyRef?
  let status = RegisterEventHotKey(
    UInt32(kVK_F20), 0, EventHotKeyID(signature: 0x484B_5150, id: 1),
    GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotkey)
  guard status == noErr else {
    print("SKIP F20 unavailable; no event posted and no binding replaced")
    return 1
  }
  defer { if let hotkey { UnregisterEventHotKey(hotkey) } }
  guard let source = CGEventSource(stateID: .privateState) else { return 1 }

  let routes: [(String, CGEventTapLocation)] =
    proxyProbe
    ? [("session-proxy", .cgSessionEventTap)]
    : handoffProbe
      ? [("session-while-annotated-held", .cgSessionEventTap)]
      : [("session", .cgSessionEventTap), ("annotated", .cgAnnotatedSessionEventTap)]
  for (name, location) in routes {
    guard
      let down = CGEvent(
        keyboardEventSource: source, virtualKey: proxyProbe ? 0xFFFF : CGKeyCode(kVK_F20),
        keyDown: true),
      let up = CGEvent(
        keyboardEventSource: source, virtualKey: proxyProbe ? 0xFFFF : CGKeyCode(kVK_F20),
        keyDown: false)
    else { return 1 }
    for event in [down, up] {
      event.flags = []
      event.setIntegerValueField(.eventSourceUserData, value: Probe.marker)
    }
    guard state.isSinkEnabled else {
      print("STOP consuming sink disabled; no pair posted")
      return 1
    }
    if handoffProbe {
      guard
        let sentinelDown = CGEvent(
          keyboardEventSource: source, virtualKey: 0xFFFF, keyDown: true),
        let sentinelUp = CGEvent(
          keyboardEventSource: source, virtualKey: 0xFFFF, keyDown: false)
      else { return 1 }
      for event in [sentinelDown, sentinelUp] {
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: Probe.marker)
        event.post(tap: .cgAnnotatedSessionEventTap)
      }
      guard state.holdEntered.wait(timeout: .now() + 0.1) == .success else {
        print("INCONCLUSIVE own sentinel did not enter gate")
        return 1
      }
    }
    let before = state.hitCount
    let consumedBefore = state.consumedCount
    down.post(tap: location)
    up.post(tap: location)
    pumpHotkeys(for: 0.12)
    let hits = state.hitCount - before
    print(name, "own hotkey hits", hits, "sink events", state.consumedCount - consumedBefore)
    if handoffProbe, hits != 1 || !state.hotkeyArrivedWhileHeld {
      print("INCONCLUSIVE native hotkey did not complete during the bounded hold")
      return 1
    }
    if name == "session" || proxyProbe, hits != 1 {
      print("INCONCLUSIVE session calibration; annotated pair not posted")
      return 1
    }
  }
  if handoffProbe {
    print("native hotkey delivered before held event release", state.hotkeyArrivedWhileHeld)
  }
  print(
    "frontmost application unchanged",
    NSWorkspace.shared.frontmostApplication?.processIdentifier == initialFrontmostPID)
  return 0
}

@main
private struct Main {
  @MainActor static func main() { exit(run()) }
}
