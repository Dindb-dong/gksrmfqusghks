import AppKit
import HanKeyCore

@MainActor
public enum SystemLexiconEvidenceProvider {
  public static func evidence(
    original: String,
    candidate: String,
    activeLanguage: TokenLanguage
  ) -> LexiconEvidence {
    LexiconEvidence(
      originalIsKnown: isKnown(original, language: activeLanguage),
      candidateIsKnown: isKnown(candidate, language: activeLanguage.opposite)
    )
  }

  private static func isKnown(_ word: String, language: TokenLanguage) -> Bool {
    let misspelled = NSSpellChecker.shared.checkSpelling(
      of: word,
      startingAt: 0,
      language: language.spellCheckerCode,
      wrap: false,
      inSpellDocumentWithTag: 0,
      wordCount: nil
    )
    return misspelled.location == NSNotFound
  }
}

extension TokenLanguage {
  fileprivate var spellCheckerCode: String {
    switch self {
    case .english:
      return "en_US"
    case .korean:
      return "ko_KR"
    }
  }
}
