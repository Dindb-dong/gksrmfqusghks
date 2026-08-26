import Carbon.HIToolbox
import CoreGraphics
import HanKeyCore

public enum GlobalInputObservation: Equatable, Sendable {
  case buffer(BufferObservation, timestampNanoseconds: UInt64)
  case tapRecovered
}

public enum HanKeySyntheticEvent {
  public static let marker: Int64 = 0x48_41_4E_4B_45_59

  public static func mark(_ event: CGEvent) {
    event.setIntegerValueField(.eventSourceUserData, value: marker)
  }

  public static func isMarked(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == marker
  }
}

public final class GlobalInputEventTap: @unchecked Sendable {
  public typealias Handler = @Sendable (GlobalInputObservation) -> Void

  private let handler: Handler
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  deinit {
    stop()
  }

  @discardableResult
  public func start() -> Bool {
    if eventTap != nil {
      return true
    }

    let events: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    let mask = events.reduce(CGEventMask(0)) { result, type in
      result | (CGEventMask(1) << type.rawValue)
    }
    let userInfo = Unmanaged.passUnretained(self).toOpaque()

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: Self.callback,
        userInfo: userInfo
      ),
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    else {
      return false
    }

    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  public func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    runLoopSource = nil
    eventTap = nil
  }

  public var isRunning: Bool {
    guard let eventTap else {
      return false
    }
    return CGEvent.tapIsEnabled(tap: eventTap)
  }

  private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
      return Unmanaged.passUnretained(event)
    }
    let owner = Unmanaged<GlobalInputEventTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = owner.eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      owner.handler(.tapRecovered)
      return Unmanaged.passUnretained(event)
    }

    guard !HanKeySyntheticEvent.isMarked(event) else {
      return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
      owner.handler(
        .buffer(.invalidate(.pointerInteraction), timestampNanoseconds: event.timestamp)
      )
    } else if type == .keyDown {
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      let observation = KeyEventInterpreter.interpret(keyCode: keyCode, flags: event.flags)
      owner.handler(.buffer(observation, timestampNanoseconds: event.timestamp))
    }

    return Unmanaged.passUnretained(event)
  }
}

enum KeyEventInterpreter {
  private static let letters: [CGKeyCode: Character] = [
    CGKeyCode(kVK_ANSI_A): "a", CGKeyCode(kVK_ANSI_B): "b", CGKeyCode(kVK_ANSI_C): "c",
    CGKeyCode(kVK_ANSI_D): "d", CGKeyCode(kVK_ANSI_E): "e", CGKeyCode(kVK_ANSI_F): "f",
    CGKeyCode(kVK_ANSI_G): "g", CGKeyCode(kVK_ANSI_H): "h", CGKeyCode(kVK_ANSI_I): "i",
    CGKeyCode(kVK_ANSI_J): "j", CGKeyCode(kVK_ANSI_K): "k", CGKeyCode(kVK_ANSI_L): "l",
    CGKeyCode(kVK_ANSI_M): "m", CGKeyCode(kVK_ANSI_N): "n", CGKeyCode(kVK_ANSI_O): "o",
    CGKeyCode(kVK_ANSI_P): "p", CGKeyCode(kVK_ANSI_Q): "q", CGKeyCode(kVK_ANSI_R): "r",
    CGKeyCode(kVK_ANSI_S): "s", CGKeyCode(kVK_ANSI_T): "t", CGKeyCode(kVK_ANSI_U): "u",
    CGKeyCode(kVK_ANSI_V): "v", CGKeyCode(kVK_ANSI_W): "w", CGKeyCode(kVK_ANSI_X): "x",
    CGKeyCode(kVK_ANSI_Y): "y", CGKeyCode(kVK_ANSI_Z): "z",
  ]

  private static let punctuation: Set<CGKeyCode> = [
    CGKeyCode(kVK_ANSI_Grave), CGKeyCode(kVK_ANSI_Minus), CGKeyCode(kVK_ANSI_Equal),
    CGKeyCode(kVK_ANSI_LeftBracket), CGKeyCode(kVK_ANSI_RightBracket),
    CGKeyCode(kVK_ANSI_Backslash), CGKeyCode(kVK_ANSI_Semicolon), CGKeyCode(kVK_ANSI_Quote),
    CGKeyCode(kVK_ANSI_Comma), CGKeyCode(kVK_ANSI_Period), CGKeyCode(kVK_ANSI_Slash),
  ]

  private static let navigation: Set<CGKeyCode> = [
    CGKeyCode(kVK_LeftArrow), CGKeyCode(kVK_RightArrow), CGKeyCode(kVK_UpArrow),
    CGKeyCode(kVK_DownArrow), CGKeyCode(kVK_Home), CGKeyCode(kVK_End), CGKeyCode(kVK_PageUp),
    CGKeyCode(kVK_PageDown), CGKeyCode(kVK_Escape), CGKeyCode(kVK_ForwardDelete),
  ]

  static func interpret(keyCode: CGKeyCode, flags: CGEventFlags) -> BufferObservation {
    let disallowedModifiers: CGEventFlags = [
      .maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn,
    ]
    if !flags.intersection(disallowedModifiers).isEmpty {
      return .invalidate(.modifiedCommand)
    }

    if let letter = letters[keyCode] {
      return .printable(
        PhysicalKeyToken(qwertyLetter: letter, isShifted: flags.contains(.maskShift))!
      )
    }

    switch Int(keyCode) {
    case kVK_Space:
      return .boundary(.space)
    case kVK_Return, kVK_ANSI_KeypadEnter:
      return .boundary(.returnKey)
    case kVK_Tab:
      return .boundary(.tab)
    case kVK_Delete:
      return .deleteBackward
    default:
      if punctuation.contains(keyCode) {
        return .boundary(.punctuation)
      }
      if navigation.contains(keyCode) {
        return .invalidate(.navigation)
      }
      return .invalidate(.unknownKey)
    }
  }
}
