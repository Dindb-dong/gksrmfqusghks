public struct PhysicalKeyToken: Equatable, Hashable, Sendable {
  public let qwertyLetter: Character
  public let isShifted: Bool

  public init?(qwertyLetter: Character, isShifted: Bool) {
    guard Self.isLowercaseASCIILetter(qwertyLetter) else {
      return nil
    }

    self.qwertyLetter = qwertyLetter
    self.isShifted = isShifted
  }

  public init?(ascii: Character) {
    guard let scalar = Self.singleScalar(for: ascii) else {
      return nil
    }

    switch scalar.value {
    case 65...90:
      let lowercase = Unicode.Scalar(scalar.value + 32)!
      self.qwertyLetter = Character(String(lowercase))
      self.isShifted = true
    case 97...122:
      self.qwertyLetter = ascii
      self.isShifted = false
    default:
      return nil
    }
  }

  public var ascii: Character {
    guard isShifted, let scalar = Self.singleScalar(for: qwertyLetter) else {
      return qwertyLetter
    }

    return Character(String(Unicode.Scalar(scalar.value - 32)!))
  }

  private static func isLowercaseASCIILetter(_ character: Character) -> Bool {
    guard let scalar = singleScalar(for: character) else {
      return false
    }
    return (97...122).contains(scalar.value)
  }

  private static func singleScalar(for character: Character) -> Unicode.Scalar? {
    let scalars = String(character).unicodeScalars
    guard scalars.count == 1 else {
      return nil
    }
    return scalars.first
  }
}
