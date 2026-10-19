import AppKit
import Carbon.HIToolbox
import Foundation
import HanKeyCore

@MainActor
public final class InputSourceController: InputSourceControlling {
  public nonisolated static let abcIdentifier = "com.apple.keylayout.ABC"
  public nonisolated static let korean2SetIdentifier = "com.apple.inputmethod.Korean.2SetKorean"

  private let readSource: @MainActor () -> InputSourceSnapshot?
  private let selectSource: @MainActor (TokenLanguage) -> Bool
  private let prepareNativeSwitch: (@MainActor () -> NativeInputSourceSwitch?)?
  private let notifications: NotificationCenter
  private let acknowledgmentDelay: @MainActor () async -> Void
  nonisolated static let sourceChanged = Notification.Name(
    kTISNotifySelectedKeyboardInputSourceChanged as String)

  public convenience init() {
    self.init(
      readSource: Self.readCurrentSource, selectSource: Self.selectSource,
      prepareNativeSwitch: Self.makeNativeSwitch)
  }

  init(
    readSource: @escaping @MainActor () -> InputSourceSnapshot?,
    selectSource: @escaping @MainActor (TokenLanguage) -> Bool,
    prepareNativeSwitch: (@MainActor () -> NativeInputSourceSwitch?)? = nil,
    notifications: NotificationCenter = DistributedNotificationCenter.default(),
    acknowledgmentDelay: @escaping @MainActor () async -> Void = {
      try? await Task.sleep(for: .milliseconds(4))
    }
  ) {
    self.readSource = readSource
    self.selectSource = selectSource
    self.prepareNativeSwitch = prepareNativeSwitch
    self.notifications = notifications
    self.acknowledgmentDelay = acknowledgmentDelay
  }

  public func currentSource() -> InputSourceSnapshot? { readSource() }

  public func select(language: TokenLanguage) -> InputSourceSnapshot? {
    guard selectSource(language), let actual = currentSource(),
      actual.identifier == Self.identifier(for: language), actual.language == language
    else { return nil }
    return actual
  }

  public func prepareSelection(language: TokenLanguage) -> PreparedInputSourceSelection? {
    guard let previous = currentSource() else { return nil }
    let desired = InputSourceSnapshot(
      identifier: Self.identifier(for: language), language: language)
    if previous == desired {
      return PreparedInputSourceSelection { isStillValid, _ in
        guard !Task.isCancelled, isStillValid(), self.currentSource() == desired else { return nil }
        return desired
      }
    }
    let native: NativeInputSourceSwitch?
    if let prepareNativeSwitch {
      guard let prepared = prepareNativeSwitch() else { return nil }
      native = prepared
    } else {
      native = nil
    }
    return PreparedInputSourceSelection { isStillValid, handoff in
      await self.confirmSelection(
        language: language, previous: previous, desired: desired,
        native: native, isStillValid: isStillValid, handoff: handoff)
    }
  }

  public func selectAndConfirm(
    language: TokenLanguage, isStillValid: @MainActor () -> Bool
  ) async -> InputSourceSnapshot? {
    guard let prepared = prepareSelection(language: language) else { return nil }
    return await prepared.perform(isStillValid: isStillValid)
  }

  private func confirmSelection(
    language: TokenLanguage, previous: InputSourceSnapshot, desired: InputSourceSnapshot,
    native: NativeInputSourceSwitch?, isStillValid: @MainActor () -> Bool,
    handoff: (any InputHandoffControlling)?
  ) async -> InputSourceSnapshot? {
    guard !Task.isCancelled, isStillValid(), currentSource() == previous else { return nil }
    let signal = SourceChangeSignal()
    if let distributed = notifications as? DistributedNotificationCenter {
      distributed.addObserver(
        signal, selector: #selector(SourceChangeSignal.receive(_:)), name: Self.sourceChanged,
        object: nil, suspensionBehavior: .deliverImmediately)
    } else {
      notifications.addObserver(
        signal, selector: #selector(SourceChangeSignal.receive(_:)), name: Self.sourceChanged,
        object: nil)
    }
    defer { notifications.removeObserver(signal) }
    guard !Task.isCancelled, isStillValid(), currentSource() == previous else { return nil }
    if let native {
      guard native.isCurrentContext(), isStillValid(), let handoff,
        handoff.canStartSourceSwitch,
        await handoff.performSourceSwitch(events: native.events)
      else { return nil }
    } else {
      guard handoff?.canStartSourceSwitch ?? true, selectSource(language) else { return nil }
    }
    for attempt in 0..<8 {
      guard !Task.isCancelled, isStillValid(), let actual = currentSource() else { return nil }
      if actual == desired, signal.received { return actual }
      guard actual == previous || actual == desired else { return nil }
      if attempt < 7 { await acknowledgmentDelay() }
    }
    return nil
  }

  private static func makeNativeSwitch() -> NativeInputSourceSwitch? {
    let hotkeys =
      CFPreferencesCopyAppValue(
        "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
      as? [String: Any]
    let properties =
      [
        kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
        kTISPropertyInputSourceIsEnabled as String: true,
        kTISPropertyInputSourceIsSelectCapable as String: true,
      ] as CFDictionary
    let sources = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray
    var identifiers: [String] = []
    for case let source as TISInputSource in sources {
      guard let identifier = stringProperty(source, key: kTISPropertyInputSourceID) else {
        return nil
      }
      identifiers.append(identifier)
    }
    guard
      NativeInputSourceSwitch.configurationIsSupported(
        hotkeys: hotkeys, enabledIdentifiers: identifiers)
    else { return nil }
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
      !IsSecureEventInputEnabled()
    else { return nil }
    return NativeInputSourceSwitch(isCurrentContext: {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        && !IsSecureEventInputEnabled()
    })
  }

  private static func readCurrentSource() -> InputSourceSnapshot? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard
      let identifier = Self.stringProperty(source, key: kTISPropertyInputSourceID),
      let language = Self.language(forIdentifier: identifier)
    else {
      return nil
    }
    return InputSourceSnapshot(identifier: identifier, language: language)
  }

  private static func selectSource(language: TokenLanguage) -> Bool {
    let desiredIdentifier = Self.identifier(for: language)
    let properties =
      [
        kTISPropertyInputSourceID as String: desiredIdentifier
      ] as CFDictionary
    let sources = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray

    for case let source as TISInputSource in sources {
      guard Self.isEnabledAndSelectable(source), TISSelectInputSource(source) == noErr else {
        continue
      }
      return true
    }
    return false
  }

  public nonisolated static func language(forIdentifier identifier: String) -> TokenLanguage? {
    switch identifier {
    case abcIdentifier:
      return .english
    case korean2SetIdentifier:
      return .korean
    default:
      return nil
    }
  }

  public nonisolated static func identifier(for language: TokenLanguage) -> String {
    switch language {
    case .english:
      return abcIdentifier
    case .korean:
      return korean2SetIdentifier
    }
  }

  private static func isEnabledAndSelectable(_ source: TISInputSource) -> Bool {
    boolProperty(source, key: kTISPropertyInputSourceIsEnabled) == true
      && boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable) == true
  }

  private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else {
      return nil
    }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
  }

  private static func boolProperty(_ source: TISInputSource, key: CFString) -> Bool? {
    guard let pointer = TISGetInputSourceProperty(source, key) else {
      return nil
    }
    return CFBooleanGetValue(
      Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
    )
  }
}

// Notification callbacks need no AX calls or typed content, only a synchronized acknowledgment bit.
private final class SourceChangeSignal: NSObject, @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  var received: Bool { lock.withLock { value } }
  @objc func receive(_ notification: Notification) { lock.withLock { value = true } }
}
