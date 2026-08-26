@preconcurrency import ApplicationServices
import CoreGraphics

@MainActor
public enum PermissionController {
  @discardableResult
  public static func requestInputMonitoring() -> Bool {
    CGRequestListenEventAccess()
  }

  @discardableResult
  public static func requestAccessibility() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
