import ApplicationServices
import Carbon.HIToolbox

@MainActor
public final class FocusedTextRewriter: FocusedTextRewriting {
  public init() {}

  public func currentSnapshot() -> FocusedTextSnapshot? {
    guard let element = focusedEditableElement() else {
      return nil
    }
    let identity = FocusedElementIdentity(
      processID: processID(of: element),
      elementHash: CFHash(element)
    )
    guard identity.processID > 0, let selection = selectedRange(of: element) else {
      return nil
    }
    return FocusedTextSnapshot(
      identity: identity,
      selection: selection,
      bundleIdentifier: FocusedElementSecurityInspector.context(for: element).bundleIdentifier
    )
  }

  public func text(
    in range: TextUTF16Range,
    matching snapshot: FocusedTextSnapshot
  ) -> String? {
    guard let element = matchingElement(snapshot.identity) else {
      return nil
    }
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
      return nil
    }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
      ) == .success
    else {
      return nil
    }
    return value as? String
  }

  public func replace(
    range: TextUTF16Range,
    with text: String,
    matching snapshot: FocusedTextSnapshot,
    isStillValid: @MainActor () -> Bool
  ) -> Bool {
    guard isStillValid(), !IsSecureEventInputEnabled(),
      let element = matchingElement(snapshot.identity),
      selectedRange(of: element) == snapshot.selection
    else {
      return false
    }
    var settable = DarwinBoolean(false)
    guard
      AXUIElementIsAttributeSettable(
        element, kAXSelectedTextAttribute as CFString, &settable
      ) == .success, settable.boolValue
    else {
      return false
    }
    guard let original = self.text(in: range, matching: snapshot)
    else { return false }
    return SelectedTextMutation.perform(
      expectedSelection: snapshot.selection, targetRange: range,
      isStillValid: {
        !IsSecureEventInputEnabled() && self.matchingElement(snapshot.identity) != nil
          && isStillValid()
      },
      selection: { self.selectedRange(of: element) },
      select: { selection in
        var value = CFRange(location: selection.location, length: selection.length)
        guard let range = AXValueCreate(.cfRange, &value) else { return .failure }
        return AXUIElementSetAttributeValue(
          element, kAXSelectedTextRangeAttribute as CFString, range)
      },
      originalIsUnchanged: { self.text(in: range, matching: snapshot) == original },
      write: {
        // A single AX mutation avoids feeding replacement letters through the active IME.
        AXUIElementSetAttributeValue(
          element, kAXSelectedTextAttribute as CFString, text as CFString)
      }
    )
  }

  private func matchingElement(_ identity: FocusedElementIdentity) -> AXUIElement? {
    guard let element = focusedEditableElement() else {
      return nil
    }
    return processID(of: element) == identity.processID && CFHash(element) == identity.elementHash
      ? element : nil
  }

  private func focusedEditableElement() -> AXUIElement? {
    guard !IsSecureEventInputEnabled() else { return nil }
    let systemWide = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(systemWide, 0.01)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedUIElementAttribute as CFString,
        &value
      ) == .success,
      let value
    else {
      return nil
    }
    let element = unsafeDowncast(value, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(element, 0.01)
    let context = FocusedElementSecurityInspector.context(for: element)
    return context.state == .editable && context.surface == .standardText ? element : nil
  }

  private func processID(of element: AXUIElement) -> pid_t {
    var processID: pid_t = 0
    return AXUIElementGetPid(element, &processID) == .success ? processID : 0
  }

  private func selectedRange(of element: AXUIElement) -> TextUTF16Range? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }
    let rangeValue = unsafeDowncast(value, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0, range.length >= 0
    else {
      return nil
    }
    return TextUTF16Range(location: range.location, length: range.length)
  }
}

// The opt-in terminal adapter still needs character-sized synthetic events.
enum UnicodeEventText {
  static func segments(_ text: String) -> [String] {
    text.map(String.init)
  }
}

// Selection restoration is allowed only after a definite rejection, never an ambiguous write timeout.
enum SelectedTextMutation {
  @MainActor
  static func perform(
    expectedSelection: TextUTF16Range, targetRange: TextUTF16Range,
    isStillValid: () -> Bool, selection: () -> TextUTF16Range?,
    select: (TextUTF16Range) -> AXError,
    originalIsUnchanged: () -> Bool, write: () -> AXError
  ) -> Bool {
    guard selection() == expectedSelection, isStillValid(),
      select(targetRange) == .success
    else { return false }
    guard selection() == targetRange, isStillValid() else { return false }
    let result = write()
    if result == .success { return true }
    let definiteRejection =
      result == .attributeUnsupported || result == .notImplemented
      || result == .illegalArgument
    if definiteRejection, isStillValid(), selection() == targetRange,
      originalIsUnchanged(), selection() == targetRange, isStillValid()
    {
      _ = select(expectedSelection)
    }
    return false
  }
}
