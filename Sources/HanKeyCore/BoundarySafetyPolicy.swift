import Foundation

public struct BoundarySafetyPolicy: Sendable {
  private static let ambiguousContinuationCharacters = CharacterSet(charactersIn: ".@/\\?")

  public init() {}

  public func permitsAutomaticCorrection(
    boundary: String,
    allowsNaturalQuestionMark: Bool = false,
    hasSettledAmbiguousBoundary: Bool = false
  ) -> Bool {
    !boundary.unicodeScalars.contains {
      if allowsNaturalQuestionMark, $0 == "?" {
        return false
      }
      return Self.ambiguousContinuationCharacters.contains($0)
        && !hasSettledAmbiguousBoundary
    }
  }

  public func requiresContinuationCheck(boundary: String) -> Bool {
    boundary.unicodeScalars.contains {
      Self.ambiguousContinuationCharacters.contains($0)
    }
  }
}
