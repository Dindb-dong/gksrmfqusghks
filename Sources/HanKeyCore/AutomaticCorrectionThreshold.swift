public struct AutomaticCorrectionThreshold: Equatable, Sendable {
  public static let validRange = 50...100
  public static let recommendedRange = 75...85
  public static let defaultValue = 75

  public let value: Int

  public init(_ value: Int) {
    self.value = min(max(value, Self.validRange.lowerBound), Self.validRange.upperBound)
  }

  public var automaticMargin: Double {
    0.5 + Double(value) / 100
  }
}
