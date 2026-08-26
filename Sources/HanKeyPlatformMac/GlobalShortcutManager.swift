import Carbon.HIToolbox

public enum ShortcutAction: UInt32, CaseIterable, Equatable, Sendable {
  case manualConvert = 1
  case undo = 2
}

public enum ShortcutPreset: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case none
  case optionSpace
  case controlOptionSpace
  case shiftOptionSpace
  case controlOptionU

  public var title: String {
    switch self {
    case .none: "지정 안 됨"
    case .optionSpace: "⌥Space"
    case .controlOptionSpace: "⌃⌥Space"
    case .shiftOptionSpace: "⇧⌥Space"
    case .controlOptionU: "⌃⌥U"
    }
  }

  fileprivate var carbonKeyCode: UInt32? {
    switch self {
    case .none: nil
    case .optionSpace, .controlOptionSpace, .shiftOptionSpace: UInt32(kVK_Space)
    case .controlOptionU: UInt32(kVK_ANSI_U)
    }
  }

  fileprivate var carbonModifiers: UInt32 {
    switch self {
    case .none: 0
    case .optionSpace: UInt32(optionKey)
    case .controlOptionSpace, .controlOptionU: UInt32(controlKey | optionKey)
    case .shiftOptionSpace: UInt32(shiftKey | optionKey)
    }
  }
}

public struct ShortcutConfiguration: Equatable, Sendable {
  public let manualConvert: ShortcutPreset
  public let undo: ShortcutPreset

  public init(manualConvert: ShortcutPreset, undo: ShortcutPreset) {
    self.manualConvert = manualConvert
    self.undo = undo
  }

  public var hasInternalCollision: Bool {
    manualConvert != .none && manualConvert == undo
  }

  public func preset(for action: ShortcutAction) -> ShortcutPreset {
    switch action {
    case .manualConvert: manualConvert
    case .undo: undo
    }
  }
}

public enum ShortcutRegistrationResult: Equatable, Sendable {
  case registered
  case disabled
  case conflict
  case unavailable
}

@MainActor
public final class GlobalShortcutManager {
  public typealias Handler = @MainActor @Sendable (ShortcutAction) -> Void

  private let handler: Handler
  private var eventHandler: EventHandlerRef?
  private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]

  public init(handler: @escaping Handler) {
    self.handler = handler
    installHandler()
  }

  public func apply(
    _ configuration: ShortcutConfiguration
  ) -> [ShortcutAction: ShortcutRegistrationResult] {
    unregisterAll()
    if configuration.hasInternalCollision {
      return [.manualConvert: .conflict, .undo: .conflict]
    }

    var results: [ShortcutAction: ShortcutRegistrationResult] = [:]
    for action in ShortcutAction.allCases {
      let preset = configuration.preset(for: action)
      guard let keyCode = preset.carbonKeyCode else {
        results[action] = .disabled
        continue
      }
      guard eventHandler != nil else {
        results[action] = .unavailable
        continue
      }
      var reference: EventHotKeyRef?
      let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
      let status = RegisterEventHotKey(
        keyCode,
        preset.carbonModifiers,
        identifier,
        GetApplicationEventTarget(),
        0,
        &reference
      )
      if status == noErr, let reference {
        hotKeys[action] = reference
        results[action] = .registered
      } else if status == eventHotKeyExistsErr {
        results[action] = .conflict
      } else {
        results[action] = .unavailable
      }
    }
    return results
  }

  public func stop() {
    unregisterAll()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
    eventHandler = nil
  }

  private static let signature: OSType = 0x484B_4559

  private func installHandler() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let userData = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      Self.eventCallback,
      1,
      &eventType,
      userData,
      &eventHandler
    )
  }

  private func unregisterAll() {
    for reference in hotKeys.values {
      UnregisterEventHotKey(reference)
    }
    hotKeys.removeAll()
  }

  private static let eventCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
      return OSStatus(eventNotHandledErr)
    }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &identifier
    )
    guard
      status == noErr,
      identifier.signature == signature,
      let action = ShortcutAction(rawValue: identifier.id)
    else {
      return OSStatus(eventNotHandledErr)
    }
    let owner = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
      owner.handler(action)
    }
    return noErr
  }
}
