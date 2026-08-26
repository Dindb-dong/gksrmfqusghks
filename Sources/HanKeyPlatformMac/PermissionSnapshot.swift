import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import HanKeyCore

public struct PermissionSnapshot: Equatable, Sendable {
  public let canMonitorInput: Bool
  public let isAccessibilityTrusted: Bool
  public let isSecureInputEnabled: Bool

  public init(
    canMonitorInput: Bool,
    isAccessibilityTrusted: Bool,
    isSecureInputEnabled: Bool
  ) {
    self.canMonitorInput = canMonitorInput
    self.isAccessibilityTrusted = isAccessibilityTrusted
    self.isSecureInputEnabled = isSecureInputEnabled
  }

  public var isReady: Bool {
    hasRequiredPermissions && !isSecureInputEnabled
  }

  public var hasRequiredPermissions: Bool {
    canMonitorInput && isAccessibilityTrusted
  }
}

public enum PlatformCapabilities {
  public static func currentPermissionSnapshot() -> PermissionSnapshot {
    PermissionSnapshot(
      canMonitorInput: CGPreflightListenEventAccess(),
      isAccessibilityTrusted: AXIsProcessTrusted(),
      isSecureInputEnabled: IsSecureEventInputEnabled()
    )
  }
}
