import Foundation

public struct ContentFreeDiagnosticReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let appVersion: String
  public let operatingSystem: String
  public let architecture: String
  public let inputMonitoringGranted: Bool
  public let accessibilityGranted: Bool
  public let secureInputActive: Bool
  public let operationalState: String
  public let learningRuleCount: Int

  public init(
    appVersion: String,
    permissions: PermissionSnapshot,
    operationalState: String,
    learningRuleCount: Int,
    operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
    architecture: String = ContentFreeDiagnosticReport.currentArchitecture
  ) {
    schemaVersion = 1
    self.appVersion = appVersion
    self.operatingSystem = operatingSystem
    self.architecture = architecture
    inputMonitoringGranted = permissions.canMonitorInput
    accessibilityGranted = permissions.isAccessibilityTrusted
    secureInputActive = permissions.isSecureInputEnabled
    self.operationalState = operationalState
    self.learningRuleCount = max(0, learningRuleCount)
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  public static var currentArchitecture: String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #else
      "unknown"
    #endif
  }
}
