import AppKit
import ApplicationServices
import HanKeyCore

public enum FocusedElementSecurityState: Equatable, Sendable {
  case editable
  case secure
  case nonEditable
  case unavailable
}

public struct AccessibilityElementDescriptor: Equatable, Sendable {
  public let role: String?
  public let subrole: String?
  public let identifier: String?
  public let roleDescription: String?

  public init(
    role: String?,
    subrole: String?,
    identifier: String? = nil,
    roleDescription: String? = nil
  ) {
    self.role = role
    self.subrole = subrole
    self.identifier = identifier
    self.roleDescription = roleDescription
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
  public let surface: InputSurface
  public let bundleIdentifier: String?

  public init(
    state: FocusedElementSecurityState,
    identity: FocusedElementIdentity?,
    surface: InputSurface,
    bundleIdentifier: String?
  ) {
    self.state = state
    self.identity = identity
    self.surface = surface
    self.bundleIdentifier = bundleIdentifier
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
      return FocusedElementContext(
        state: .unavailable,
        identity: nil,
        surface: .unsupported,
        bundleIdentifier: nil
      )
    }

    let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
    return context(for: element)
  }

  static func context(for element: AXUIElement) -> FocusedElementContext {
    let descriptor = AccessibilityElementDescriptor(
      role: stringAttribute(kAXRoleAttribute as CFString, element: element),
      subrole: stringAttribute(kAXSubroleAttribute as CFString, element: element),
      identifier: stringAttribute(kAXIdentifierAttribute as CFString, element: element),
      roleDescription: stringAttribute(kAXRoleDescriptionAttribute as CFString, element: element)
    )
    let state = classify(descriptor)
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
    let bundleIdentifier = identity.flatMap {
      NSRunningApplication(processIdentifier: $0.processID)?.bundleIdentifier
    }
    let surface = InputSurfaceInspector.classify(
      bundleIdentifier: bundleIdentifier,
      descriptor: descriptor,
      securityState: state
    )
    return FocusedElementContext(
      state: state,
      identity: identity,
      surface: surface,
      bundleIdentifier: bundleIdentifier
    )
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
