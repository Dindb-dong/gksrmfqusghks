import ApplicationServices
import CoreGraphics

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
    return FocusedTextSnapshot(identity: identity, selection: selection)
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
    matching snapshot: FocusedTextSnapshot
  ) -> Bool {
    guard let element = matchingElement(snapshot.identity) else {
      return false
    }
    var cfRange = CFRange(location: range.location, length: range.length)
    guard
      let rangeValue = AXValueCreate(.cfRange, &cfRange),
      AXUIElementSetAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        rangeValue
      ) == .success,
      let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else {
      return false
    }

    let utf16 = Array(text.utf16)
    utf16.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return
      }
      keyDown.keyboardSetUnicodeString(
        stringLength: buffer.count,
        unicodeString: baseAddress
      )
      keyUp.keyboardSetUnicodeString(
        stringLength: buffer.count,
        unicodeString: baseAddress
      )
    }
    HanKeySyntheticEvent.mark(keyDown)
    HanKeySyntheticEvent.mark(keyUp)
    keyDown.postToPid(snapshot.identity.processID)
    keyUp.postToPid(snapshot.identity.processID)
    return true
  }

  private func matchingElement(_ identity: FocusedElementIdentity) -> AXUIElement? {
    guard let element = focusedEditableElement() else {
      return nil
    }
    return processID(of: element) == identity.processID && CFHash(element) == identity.elementHash
      ? element : nil
  }

  private func focusedEditableElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
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
