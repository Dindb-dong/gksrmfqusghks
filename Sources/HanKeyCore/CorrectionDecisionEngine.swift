public enum ExplicitCorrectionRule: String, Equatable, Sendable {
  case none
  case always
  case never
}

public struct LexiconEvidence: Equatable, Sendable {
  public let originalIsKnown: Bool
  public let candidateIsKnown: Bool

  public init(originalIsKnown: Bool, candidateIsKnown: Bool) {
    self.originalIsKnown = originalIsKnown
    self.candidateIsKnown = candidateIsKnown
  }
}

public struct CorrectionRequest: Equatable, Sendable {
  public let token: String
  public let activeLanguage: TokenLanguage
  public let surface: InputSurface
  public let isApplicationExcluded: Bool
  public let explicitRule: ExplicitCorrectionRule
  public let lexiconEvidence: LexiconEvidence

  public init(
    token: String,
    activeLanguage: TokenLanguage,
    surface: InputSurface = .standardText,
    isApplicationExcluded: Bool = false,
    explicitRule: ExplicitCorrectionRule = .none,
    lexiconEvidence: LexiconEvidence
  ) {
    self.token = token
    self.activeLanguage = activeLanguage
    self.surface = surface
    self.isApplicationExcluded = isApplicationExcluded
    self.explicitRule = explicitRule
    self.lexiconEvidence = lexiconEvidence
  }
}

public struct CorrectionProposal: Equatable, Sendable {
  public let original: String
  public let replacement: String
  public let targetLanguage: TokenLanguage
  public let confidence: Double
  public let usedExplicitRule: Bool
}

public enum NoCorrectionReason: Equatable, Sendable {
  case unsafe(SafetyExclusionReason)
  case explicitNever
  case noAlternative
  case originalIsKnown
  case insufficientCandidateEvidence
  case insufficientMargin
}

public enum CorrectionDecision: Equatable, Sendable {
  case correct(CorrectionProposal)
  case noCorrection(NoCorrectionReason)
}

public struct CorrectionDecisionEngine: Sendable {
  public let automaticMargin: Double
  private let safetyClassifier: TokenSafetyClassifier
  private let scorer: TokenLanguageScorer

  public init(
    automaticMargin: Double = 1.25,
    safetyClassifier: TokenSafetyClassifier = TokenSafetyClassifier(),
    scorer: TokenLanguageScorer = TokenLanguageScorer()
  ) {
    self.automaticMargin = automaticMargin
    self.safetyClassifier = safetyClassifier
    self.scorer = scorer
  }

  public func decide(_ request: CorrectionRequest) -> CorrectionDecision {
    switch safetyClassifier.classify(
      token: request.token,
      surface: request.surface,
      isApplicationExcluded: request.isApplicationExcluded
    ) {
    case .excluded(let reason):
      return .noCorrection(.unsafe(reason))
    case .eligible:
      break
    }

    if request.explicitRule == .never {
      return .noCorrection(.explicitNever)
    }

    let candidate = convertedCandidate(for: request)
    guard !candidate.isEmpty, candidate != request.token else {
      return .noCorrection(.noAlternative)
    }

    if request.explicitRule == .always {
      return .correct(
        CorrectionProposal(
          original: request.token,
          replacement: candidate,
          targetLanguage: request.activeLanguage.opposite,
          confidence: 1,
          usedExplicitRule: true
        )
      )
    }

    if request.lexiconEvidence.originalIsKnown {
      return .noCorrection(.originalIsKnown)
    }

    let originalScore = scorer.score(
      request.token,
      as: request.activeLanguage,
      isKnown: request.lexiconEvidence.originalIsKnown
    )
    let candidateScore = scorer.score(
      candidate,
      as: request.activeLanguage.opposite,
      isKnown: request.lexiconEvidence.candidateIsKnown
    )

    let hasEvidence =
      request.lexiconEvidence.candidateIsKnown
      || strongKoreanToEnglishMismatch(request: request, candidateScore: candidateScore)
    guard hasEvidence else {
      return .noCorrection(.insufficientCandidateEvidence)
    }

    let margin = candidateScore.total - originalScore.total
    guard margin >= automaticMargin else {
      return .noCorrection(.insufficientMargin)
    }

    return .correct(
      CorrectionProposal(
        original: request.token,
        replacement: candidate,
        targetLanguage: request.activeLanguage.opposite,
        confidence: min(1, max(0, margin / 3)),
        usedExplicitRule: false
      )
    )
  }

  private func convertedCandidate(for request: CorrectionRequest) -> String {
    switch request.activeLanguage {
    case .english:
      return DubeolsikConverter.compose(request.token)
    case .korean:
      return DubeolsikConverter.decomposeToQWERTY(request.token)
    }
  }

  private func strongKoreanToEnglishMismatch(
    request: CorrectionRequest,
    candidateScore: TokenScore
  ) -> Bool {
    guard request.activeLanguage == .korean else {
      return false
    }
    let originalScore = scorer.score(request.token, as: .korean, isKnown: false)
    return originalScore.malformedScriptRatio >= 0.5 && candidateScore.total >= 0.9
  }
}
