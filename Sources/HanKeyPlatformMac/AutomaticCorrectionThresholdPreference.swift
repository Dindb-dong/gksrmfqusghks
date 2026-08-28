import Foundation
import HanKeyCore

@MainActor
public final class AutomaticCorrectionThresholdPreference {
  public static let key = "automaticCorrectionThreshold"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var value: Int {
    guard defaults.object(forKey: Self.key) != nil else {
      return AutomaticCorrectionThreshold.defaultValue
    }
    return AutomaticCorrectionThreshold(defaults.integer(forKey: Self.key)).value
  }

  public func setValue(_ value: Int) {
    defaults.set(AutomaticCorrectionThreshold(value).value, forKey: Self.key)
  }
}
