import Foundation

public struct BoundarySafetyPolicy: Sendable {
  private static let unsafeContinuationCharacters = CharacterSet(charactersIn: ".@/\\?")

  public init() {}

  public func permitsAutomaticCorrection(
    boundary: String,
    allowsNaturalQuestionMark: Bool = false
  ) -> Bool {
    !boundary.unicodeScalars.contains {
      if allowsNaturalQuestionMark, $0 == "?" {
        return false
      }
      return Self.unsafeContinuationCharacters.contains($0)
    }
  }
}
