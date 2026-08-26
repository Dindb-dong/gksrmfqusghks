import Foundation

public enum InputSurface: String, Equatable, Sendable {
  case standardText
  case browserAddressBar
  case terminal
  case ide
  case passwordManager
  case remoteDesktop
  case secureTextField
  case unsupported

  public var prohibitsAutomaticCorrection: Bool {
    self != .standardText
  }
}

public enum SafetyExclusionReason: String, Equatable, Sendable {
  case protectedSurface
  case excludedApplication
  case tooShort
  case tooLong
  case whitespace
  case networkAddressOrPath
  case uuid
  case hash
  case numeric
  case codeIdentifier
  case allCaps
  case mixedScript
  case punctuation
  case highEntropy
}

public enum TokenSafetyResult: Equatable, Sendable {
  case eligible
  case excluded(SafetyExclusionReason)
}

public struct TokenSafetyClassifier: Sendable {
  public let minimumLength: Int
  public let maximumLength: Int

  public init(minimumLength: Int = 3, maximumLength: Int = 64) {
    self.minimumLength = minimumLength
    self.maximumLength = maximumLength
  }

  public func classify(
    token: String,
    surface: InputSurface,
    isApplicationExcluded: Bool = false
  ) -> TokenSafetyResult {
    if surface.prohibitsAutomaticCorrection {
      return .excluded(.protectedSurface)
    }
    if isApplicationExcluded {
      return .excluded(.excludedApplication)
    }
    if token.count < minimumLength {
      return .excluded(.tooShort)
    }
    if token.count > maximumLength {
      return .excluded(.tooLong)
    }
    if token.contains(where: { $0.isWhitespace }) {
      return .excluded(.whitespace)
    }
    if looksLikeNetworkAddressOrPath(token) {
      return .excluded(.networkAddressOrPath)
    }
    if looksLikeUUID(token) {
      return .excluded(.uuid)
    }
    if looksLikeHash(token) {
      return .excluded(.hash)
    }
    if token.contains(where: { $0.isNumber }) {
      return .excluded(.numeric)
    }
    if looksLikeCodeIdentifier(token) {
      return .excluded(.codeIdentifier)
    }
    if isAllCapsASCII(token) {
      return .excluded(.allCaps)
    }

    let scripts = scripts(in: token)
    if scripts.contains(.latin), scripts.contains(.hangul) {
      return .excluded(.mixedScript)
    }
    if scripts.contains(.other) {
      return .excluded(.punctuation)
    }
    if token.count >= 12, shannonEntropy(token) >= 3.5 {
      return .excluded(.highEntropy)
    }

    return .eligible
  }

  private func looksLikeNetworkAddressOrPath(_ token: String) -> Bool {
    let lowered = token.lowercased()
    return lowered.contains("://")
      || lowered.hasPrefix("www.")
      || lowered.contains("@")
      || lowered.contains("/")
      || lowered.contains("\\")
      || lowered.hasPrefix("~")
      || lowered.contains(".")
  }

  private func looksLikeUUID(_ token: String) -> Bool {
    let segments = token.split(separator: "-", omittingEmptySubsequences: false)
    guard segments.map(\.count) == [8, 4, 4, 4, 12] else {
      return false
    }
    return segments.joined().allSatisfy(\.isHexDigit)
  }

  private func looksLikeHash(_ token: String) -> Bool {
    token.count >= 16 && token.allSatisfy(\.isHexDigit)
  }

  private func looksLikeCodeIdentifier(_ token: String) -> Bool {
    if token.contains("_") || token.contains("-") {
      return true
    }

    var sawLowercase = false
    for character in token {
      if character.isLowercase {
        sawLowercase = true
      } else if character.isUppercase, sawLowercase {
        return true
      }
    }
    return false
  }

  private func isAllCapsASCII(_ token: String) -> Bool {
    let letters = token.filter { $0.isASCII && $0.isLetter }
    return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
  }

  private func shannonEntropy(_ token: String) -> Double {
    let values = Array(token.unicodeScalars.map(\.value))
    let total = Double(values.count)
    let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
    return counts.values.reduce(0) { entropy, count in
      let probability = Double(count) / total
      return entropy - probability * log2(probability)
    }
  }

  private enum Script {
    case latin
    case hangul
    case other
  }

  private func scripts(in token: String) -> Set<Script> {
    Set(
      token.unicodeScalars.map { scalar in
        if scalar.isASCII, CharacterSet.letters.contains(scalar) {
          return .latin
        }
        if Self.isHangul(scalar.value) {
          return .hangul
        }
        return .other
      })
  }

  static func isHangul(_ scalar: UInt32) -> Bool {
    (0xAC00...0xD7A3).contains(scalar)
      || (0x1100...0x11FF).contains(scalar)
      || (0x3130...0x318F).contains(scalar)
      || (0xA960...0xA97F).contains(scalar)
      || (0xD7B0...0xD7FF).contains(scalar)
  }
}
