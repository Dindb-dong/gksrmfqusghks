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
  private var tap: CFMachPort?
  private var loop: CFRunLoop?

  var hitCount: Int { lock.withLock { hits } }
  var isSinkEnabled: Bool {
    lock.withLock { tap.map { CGEvent.tapIsEnabled(tap: $0) } == true }
  }
  func receiveHotkey() { lock.withLock { hits += 1 } }

  func startSink() -> Bool {
    Thread { [self] in
      let callback: CGEventTapCallBack = { _, _, event, _ in
        // Only our private marker is consumed. All user events pass immediately.
        if event.getIntegerValueField(.eventSourceUserData) == Probe.marker,
          event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_F20)
        {
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
          eventsOfInterest: mask, callback: callback, userInfo: nil),
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
      ready.signal()
      CFRunLoopRun()
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }.start()
    guard ready.wait(timeout: .now() + .seconds(1)) == .success else { return false }
    return lock.withLock { tap.map { CGEvent.tapIsEnabled(tap: $0) } == true }
  }

  func stopSink() {
    if let runloop = lock.withLock({ loop }) {
      CFRunLoopStop(runloop)
      CFRunLoopWakeUp(runloop)
    }
  }
}

@MainActor
private func run() -> Int32 {
  guard CommandLine.arguments.dropFirst().elementsEqual(["--allow-session-test-events"]) else {
    print("Not run: explicit --allow-session-test-events authorization is required")
    return 64
  }
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let initialFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
  let state = Probe()
  defer { state.stopSink() }
  guard state.startSink() else {
    print("SKIP consuming sink unavailable")
    return 1
  }

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

  for (name, location) in [
    ("session", CGEventTapLocation.cgSessionEventTap),
    ("annotated", .cgAnnotatedSessionEventTap),
  ] {
    guard
      let down = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_F20), keyDown: true),
      let up = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_F20), keyDown: false)
    else { return 1 }
    for event in [down, up] {
      event.flags = []
      event.setIntegerValueField(.eventSourceUserData, value: Probe.marker)
    }
    guard state.isSinkEnabled else {
      print("STOP consuming sink disabled; no pair posted")
      return 1
    }
    let before = state.hitCount
    down.post(tap: location)
    up.post(tap: location)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
    let hits = state.hitCount - before
    print(name, "own hotkey hits", hits)
    if name == "session", hits != 1 {
      print("INCONCLUSIVE session calibration; annotated pair not posted")
      return 1
    }
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
