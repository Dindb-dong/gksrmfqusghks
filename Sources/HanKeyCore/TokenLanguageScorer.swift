public enum TokenLanguage: String, Equatable, Sendable {
  case english
  case korean

  public var opposite: TokenLanguage {
    self == .english ? .korean : .english
  }
}

public struct TokenScore: Equatable, Sendable {
  public let total: Double
  public let malformedScriptRatio: Double

  public init(total: Double, malformedScriptRatio: Double) {
    self.total = total
    self.malformedScriptRatio = malformedScriptRatio
  }
}

public struct TokenLanguageScorer: Sendable {
  private static let commonEnglishBigrams: Set<String> = [
    "an", "ar", "at", "ch", "en", "er", "es", "he", "in", "ng", "on", "or", "re", "se", "st", "th",
  ]

  public init() {}

  public func score(_ token: String, as language: TokenLanguage, isKnown: Bool) -> TokenScore {
    switch language {
    case .english:
      return scoreEnglish(token, isKnown: isKnown)
    case .korean:
      return scoreKorean(token, isKnown: isKnown)
    }
  }

  private func scoreEnglish(_ token: String, isKnown: Bool) -> TokenScore {
    let lowered = token.lowercased()
    guard !lowered.isEmpty, lowered.allSatisfy({ $0.isASCII && $0.isLetter }) else {
      return TokenScore(total: -2, malformedScriptRatio: 1)
    }

    let characters = Array(lowered)
    let vowelCount = characters.filter { "aeiouy".contains($0) }.count
    let vowelRatio = Double(vowelCount) / Double(characters.count)
    var score = 0.4

    if (0.2...0.7).contains(vowelRatio) {
      score += 0.5
    } else if characters.count >= 4 {
      score -= 0.8
    }

    if characters.count >= 2 {
      let bigrams = zip(characters, characters.dropFirst()).map { String([$0, $1]) }
      let matches = bigrams.filter(Self.commonEnglishBigrams.contains).count
      score += min(0.8, Double(matches) / Double(max(1, bigrams.count)) * 1.2)
    }

    if hasConsonantRun(characters, length: 4) {
      score -= 0.8
    }
    if let q = characters.firstIndex(of: "q") {
      let next = characters.index(after: q)
      if next == characters.endIndex || characters[next] != "u" {
        score -= 0.4
      }
    }
    if isKnown {
      score += 1.5
    }

    return TokenScore(total: score, malformedScriptRatio: 0)
  }

  private func scoreKorean(_ token: String, isKnown: Bool) -> TokenScore {
    guard !token.isEmpty else {
      return TokenScore(total: -2, malformedScriptRatio: 1)
    }

    var hangulScalars = 0
    var compatibilityJamo = 0
    var precomposedSyllables = 0

    for scalar in token.unicodeScalars {
      if TokenSafetyClassifier.isHangul(scalar.value) {
        hangulScalars += 1
      }
      if (0x3130...0x318F).contains(scalar.value) {
        compatibilityJamo += 1
      }
      if (0xAC00...0xD7A3).contains(scalar.value) {
        precomposedSyllables += 1
      }
    }

    guard hangulScalars == token.unicodeScalars.count else {
      return TokenScore(total: -2, malformedScriptRatio: 1)
    }

    let count = Double(max(1, hangulScalars))
    let malformedRatio = Double(compatibilityJamo) / count
    var score = Double(precomposedSyllables) / count - malformedRatio * 1.5
    if isKnown {
      score += 1.5
    }
    return TokenScore(total: score, malformedScriptRatio: malformedRatio)
  }

  private func hasConsonantRun(_ characters: [Character], length: Int) -> Bool {
    var run = 0
    for character in characters {
      if "aeiouy".contains(character) {
        run = 0
      } else {
        run += 1
        if run >= length {
          return true
        }
      }
    }
    return false
  }
}
