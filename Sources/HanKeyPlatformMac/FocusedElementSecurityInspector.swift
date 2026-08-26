import ApplicationServices

public enum FocusedElementSecurityState: Equatable, Sendable {
  case editable
  case secure
  case nonEditable
  case unavailable
}

public struct AccessibilityElementDescriptor: Equatable, Sendable {
  public let role: String?
  public let subrole: String?

  public init(role: String?, subrole: String?) {
    self.role = role
    self.subrole = subrole
  }
}

public struct FocusedElementIdentity: Equatable, Sendable {
  public let processID: Int32
  public let elementHash: UInt

  public init(processID: Int32, elementHash: UInt) {
    self.processID = processID
    self.elementHash = elementHash
  }
}

public struct FocusedElementContext: Equatable, Sendable {
  public let state: FocusedElementSecurityState
  public let identity: FocusedElementIdentity?

  public init(state: FocusedElementSecurityState, identity: FocusedElementIdentity?) {
    self.state = state
    self.identity = identity
  }
}

public enum FocusedElementSecurityInspector {
  public static func currentState() -> FocusedElementSecurityState {
    currentContext().state
  }

  public static func currentContext() -> FocusedElementContext {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedUIElementAttribute as CFString,
        &focusedValue
      ) == .success,
      let focusedValue
    else {
      return FocusedElementContext(state: .unavailable, identity: nil)
    }

    let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
    let state = classify(
      AccessibilityElementDescriptor(
        role: stringAttribute(kAXRoleAttribute as CFString, element: element),
        subrole: stringAttribute(kAXSubroleAttribute as CFString, element: element)
      )
    )
    var processID: pid_t = 0
    let identity: FocusedElementIdentity?
    if AXUIElementGetPid(element, &processID) == .success {
      identity = FocusedElementIdentity(
        processID: processID,
        elementHash: CFHash(element)
      )
    } else {
      identity = nil
    }
    return FocusedElementContext(state: state, identity: identity)
  }

  public static func classify(
    _ descriptor: AccessibilityElementDescriptor
  ) -> FocusedElementSecurityState {
    if descriptor.subrole == (kAXSecureTextFieldSubrole as String) {
      return .secure
    }

    let editableRoles: Set<String> = [
      kAXTextFieldRole as String,
      kAXTextAreaRole as String,
      kAXComboBoxRole as String,
    ]
    if let role = descriptor.role, editableRoles.contains(role) {
      return .editable
    }
    return descriptor.role == nil ? .unavailable : .nonEditable
  }

  private static func stringAttribute(_ attribute: CFString, element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value as? String
  }
}

struct FocusIdentityTracker {
  private(set) var current: FocusedElementIdentity?

  mutating func update(_ identity: FocusedElementIdentity?) -> Bool {
    defer { current = identity }
    guard let current, let identity else {
      return false
    }
    return current != identity
  }

  mutating func reset() {
    current = nil
  }
}
