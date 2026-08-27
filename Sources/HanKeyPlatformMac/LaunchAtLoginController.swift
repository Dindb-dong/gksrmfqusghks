import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case repairRequired

  public var isEnabled: Bool {
    self == .enabled
  }

  public var title: String {
    switch self {
    case .notRegistered: "꺼짐"
    case .enabled: "켜짐"
    case .requiresApproval: "시스템 설정 승인 필요"
    case .repairRequired: "등록 복구 필요"
    }
  }
}

@MainActor
public final class LaunchAtLoginController {
  private let service: SMAppService

  public init(service: SMAppService = .mainApp) {
    self.service = service
  }

  public var status: LaunchAtLoginStatus {
    Self.map(service.status)
  }

  public func setEnabled(_ enabled: Bool) async throws {
    if enabled {
      guard service.status != .enabled, service.status != .requiresApproval else {
        return
      }
      try service.register()
    } else if service.status != .notRegistered {
      try await service.unregister()
    }
  }

  public func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  nonisolated static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
    switch status {
    case .notRegistered: .notRegistered
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .repairRequired
    @unknown default: .repairRequired
    }
  }
}
