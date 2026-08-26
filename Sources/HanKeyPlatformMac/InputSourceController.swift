import Carbon.HIToolbox
import HanKeyCore

@MainActor
public final class InputSourceController: InputSourceControlling {
  public nonisolated static let abcIdentifier = "com.apple.keylayout.ABC"
  public nonisolated static let korean2SetIdentifier = "com.apple.inputmethod.Korean.2SetKorean"

  public init() {}

  public func currentSource() -> InputSourceSnapshot? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard
      let identifier = Self.stringProperty(source, key: kTISPropertyInputSourceID),
      let language = Self.language(forIdentifier: identifier)
    else {
      return nil
    }
    return InputSourceSnapshot(identifier: identifier, language: language)
  }

  public func select(language: TokenLanguage) -> InputSourceSnapshot? {
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
      return InputSourceSnapshot(identifier: desiredIdentifier, language: language)
    }
    return nil
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
