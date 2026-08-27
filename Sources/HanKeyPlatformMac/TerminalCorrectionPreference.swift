import Foundation

@MainActor
public final class TerminalCorrectionPreference {
  public static let key = "terminalCorrectionEnabled"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var isEnabled: Bool {
    defaults.bool(forKey: Self.key)
  }

  public func setEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.key)
  }
}
