import Carbon.HIToolbox
import CoreGraphics
import Foundation
import HanKeyCore

/// Prebuilt native previous-source chord; the input gate owns ordered start and cleanup.
final class NativeInputSourceSwitch: @unchecked Sendable {
  let events: [CGEvent]
  let isCurrentContext: @MainActor @Sendable () -> Bool

  static func configurationIsSupported(
    hotkeys: [String: Any]?, enabledIdentifiers: [String]
  ) -> Bool {
    guard
      Set(enabledIdentifiers) == [
        InputSourceController.abcIdentifier, InputSourceController.korean2SetIdentifier,
      ], enabledIdentifiers.count == 2,
      let previous = hotkeys?["60"] as? [String: Any],
      let enabled = previous["enabled"] as? Bool, enabled,
      let value = previous["value"] as? [String: Any], value["type"] as? String == "standard",
      let parameters = value["parameters"] as? [Int],
      parameters == [32, Int(kVK_Space), Int(CGEventFlags.maskControl.rawValue)]
    else { return false }
    return true
  }

  init?(isCurrentContext: @escaping @MainActor @Sendable () -> Bool = { true }) {
    self.isCurrentContext = isCurrentContext
    guard let source = CGEventSource(stateID: .privateState) else { return nil }
    let definitions: [(CGKeyCode, Bool, CGEventType, CGEventFlags)] = [
      (CGKeyCode(kVK_Control), true, .flagsChanged, .maskControl),
      (CGKeyCode(kVK_Space), true, .keyDown, .maskControl),
      (CGKeyCode(kVK_Space), false, .keyUp, .maskControl),
      (CGKeyCode(kVK_Control), false, .flagsChanged, []),
    ]
    var prepared: [CGEvent] = []
    for (key, down, type, flags) in definitions {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
      else { return nil }
      event.type = type
      event.flags = flags
      HanKeySyntheticEvent.mark(event)
      prepared.append(event)
    }
    events = prepared
  }

}
