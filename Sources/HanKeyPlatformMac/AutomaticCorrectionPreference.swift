import Foundation

@MainActor
public final class AutomaticCorrectionPreference {
  public static let key = "automaticCorrectionEnabled"

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
