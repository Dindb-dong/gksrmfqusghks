import AppKit
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
      bundleIdentifier: NSRunningApplication(processIdentifier: identity.processID)?
        .bundleIdentifier
    )
  }

  public func text(
    in range: TextUTF16Range,
    matching snapshot: FocusedTextSnapshot
  ) -> String? {
    guard let element = matchingElement(snapshot.identity) else {
      return nil
    }
    return rangedText(in: range, element: element)
  }

  private func rangedText(in range: TextUTF16Range, element: AXUIElement) -> String? {
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
    range: TextUTF16Range, with text: String, matching snapshot: FocusedTextSnapshot,
    isStillValid: @MainActor () -> Bool
  ) -> Bool {
    guard let original = self.text(in: range, matching: snapshot) else { return false }
    return prepareReplacement(range: range, with: text, expectedText: original, matching: snapshot)?
      .perform(isStillValid: isStillValid) ?? false
  }

  public func prepareReplacement(
    range: TextUTF16Range,
    with text: String,
    expectedText: String,
    matching snapshot: FocusedTextSnapshot
  ) -> PreparedTextReplacement? {
    guard !Task.isCancelled, !IsSecureEventInputEnabled(),
      let element = matchingElement(snapshot.identity),
      selectedRange(of: element) == snapshot.selection,
      rangedText(in: range, element: element) == expectedText
    else {
      return nil
    }
    var cfRange = CFRange(location: range.location, length: range.length)
    guard
      let rangeValue = AXValueCreate(.cfRange, &cfRange),
      let source = CGEventSource(stateID: .combinedSessionState)
    else {
      return nil
    }

    let segments = UnicodeEventText.segments(text)
    let events = segments.compactMap { segment -> (CGEvent, CGEvent)? in
      guard
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      else {
        return nil
      }

      let utf16 = Array(segment.utf16)
      utf16.withUnsafeBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
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
      return (keyDown, keyUp)
    }
    guard !events.isEmpty, events.count == segments.count else {
      return nil
    }
    return PreparedTextReplacement { isStillValid in
      // Keep selection and dispatch contiguous, as in the working 1.0.1 transport.
      guard !Task.isCancelled, !IsSecureEventInputEnabled(),
        self.matchingElement(snapshot.identity) != nil,
        self.selectedRange(of: element) == snapshot.selection,
        self.rangedText(in: range, element: element) == expectedText,
        NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.identity.processID,
        !IsSecureEventInputEnabled(), isStillValid()
      else { return false }
      guard
        AXUIElementSetAttributeValue(
          element,
          kAXSelectedTextRangeAttribute as CFString,
          rangeValue
        ) == .success
      else {
        return false
      }

      for (keyDown, keyUp) in events {
        keyDown.postToPid(snapshot.identity.processID)
        keyUp.postToPid(snapshot.identity.processID)
      }
      return true
    }
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
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.01)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application,
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
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
      return nil
    }
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

// Keep the working character-sized Unicode transport for standard and opt-in terminal input.
enum UnicodeEventText {
  static func segments(_ text: String) -> [String] {
    text.map(String.init)
  }
}
