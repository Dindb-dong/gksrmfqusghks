import Foundation

public struct BoundarySafetyPolicy: Sendable {
  private static let unsafeContinuationCharacters = CharacterSet(charactersIn: ".@/\\_-")

  public init() {}

  public func permitsAutomaticCorrection(boundary: String) -> Bool {
    !boundary.unicodeScalars.contains {
      Self.unsafeContinuationCharacters.contains($0)
    }
  }
}
