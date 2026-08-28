import HanKeyCore
import XCTest

final class CorrectionDecisionEngineTests: XCTestCase {
  private let engine = CorrectionDecisionEngine()

  func testCorrectsKnownKoreanCandidateFromEnglishLayout() throws {
    let proposal = try correction(
      for: request(
        token: "gksrmffh",
        activeLanguage: .english,
        candidateKnown: true
      )
    )
    XCTAssertEqual(proposal.replacement, "한글로")
    XCTAssertEqual(proposal.targetLanguage, .korean)
    XCTAssertFalse(proposal.usedExplicitRule)
  }

  func testCorrectsMalformedKoreanJamoIntoEnglish() throws {
    let proposal = try correction(
      for: request(token: "ㅛㅐㅜㄴ댜", activeLanguage: .korean)
    )
    XCTAssertEqual(proposal.replacement, "yonsei")
    XCTAssertEqual(proposal.targetLanguage, .english)
  }

  func testCorrectsHamburgerPhysicalSequenceFromKoreanLayout() throws {
    let malformed = DubeolsikConverter.compose("hamburger")
    XCTAssertEqual(malformed, "ㅗ므ㅠㅕㄱㅎㄷㄱ")

    let proposal = try correction(
      for: request(
        token: malformed,
        activeLanguage: .korean,
        candidateKnown: true
      )
    )

    XCTAssertEqual(proposal.replacement, "hamburger")
    XCTAssertEqual(proposal.targetLanguage, .english)
  }

  func testCommandPrefixesCorrectOnlyHighConfidenceMalformedKorean() throws {
    let slashOriginal = DubeolsikConverter.compose("compact")
    XCTAssertEqual(slashOriginal, "채ㅡㅔㅁㅊㅅ")
    XCTAssertEqual(
      try correction(
        for: request(
          token: slashOriginal,
          activeLanguage: .korean,
          leadingCommandPrefix: .slash,
          originalKnown: true,
          candidateKnown: true
        )
      ).replacement,
      "compact"
    )

    let optionOriginal = DubeolsikConverter.compose("help")
    XCTAssertEqual(
      try correction(
        for: request(
          token: optionOriginal,
          activeLanguage: .korean,
          leadingCommandPrefix: .doubleHyphen,
          candidateKnown: true
        )
      ).replacement,
      "help"
    )

    let shortOptionOriginal = DubeolsikConverter.compose("v")
    XCTAssertEqual(
      try correction(
        for: request(
          token: shortOptionOriginal,
          activeLanguage: .korean,
          leadingCommandPrefix: .singleHyphen
        )
      ).replacement,
      "v"
    )
  }

  func testCommandPrefixesFailClosedForKoreanUnknownAndProtectedInputs() {
    XCTAssertEqual(
      engine.decide(
        request(
          token: "도움말",
          activeLanguage: .korean,
          leadingCommandPrefix: .slash,
          candidateKnown: true
        )
      ),
      .noCorrection(.insufficientCandidateEvidence)
    )
    XCTAssertEqual(
      engine.decide(
        request(
          token: "ㅁㅠㅊ",
          activeLanguage: .korean,
          leadingCommandPrefix: .slash
        )
      ),
      .noCorrection(.insufficientCandidateEvidence)
    )
    XCTAssertEqual(
      engine.decide(
        request(
          token: DubeolsikConverter.compose("compact"),
          activeLanguage: .korean,
          surface: .browserAddressBar,
          leadingCommandPrefix: .slash,
          candidateKnown: true
        )
      ),
      .noCorrection(.unsafe(.protectedSurface))
    )
  }

  func testKnownOriginalAndUnknownCandidateAreNotCorrected() {
    XCTAssertEqual(
      engine.decide(
        request(token: "hello", activeLanguage: .english, originalKnown: true)
      ),
      .noCorrection(.originalIsKnown)
    )
    XCTAssertEqual(
      engine.decide(request(token: "gksrmffh", activeLanguage: .english)),
      .noCorrection(.insufficientCandidateEvidence)
    )
  }

  func testAutomaticMarginChangesOnlyOrdinaryScoredDecisions() throws {
    let scoredRequest = request(
      token: "ahem",
      activeLanguage: .english,
      candidateKnown: true
    )

    XCTAssertEqual(
      CorrectionDecisionEngine(automaticMargin: 1.5).decide(scoredRequest),
      .noCorrection(.insufficientMargin)
    )
    guard case .correct = CorrectionDecisionEngine(automaticMargin: 1).decide(scoredRequest) else {
      return XCTFail("A lower threshold should accept the same scored candidate")
    }

    let explicitProposal = try correction(
      for: request(
        token: "gksrmffh",
        activeLanguage: .english,
        explicitRule: .always
      ),
      using: CorrectionDecisionEngine(automaticMargin: .infinity)
    )
    XCTAssertTrue(explicitProposal.usedExplicitRule)
  }

  func testExplicitRulesRespectHardSafetyBoundary() throws {
    let always = try correction(
      for: request(
        token: "gksrmffh",
        activeLanguage: .english,
        explicitRule: .always
      )
    )
    XCTAssertTrue(always.usedExplicitRule)

    XCTAssertEqual(
      engine.decide(
        request(
          token: "gksrmffh",
          activeLanguage: .english,
          surface: .secureTextField,
          explicitRule: .always
        )
      ),
      .noCorrection(.unsafe(.protectedSurface))
    )
    XCTAssertEqual(
      engine.decide(
        request(
          token: "gksrmffh",
          activeLanguage: .english,
          explicitRule: .never,
          candidateKnown: true
        )
      ),
      .noCorrection(.explicitNever)
    )
  }

  func testAdversarialTokensNeverReachCorrection() {
    let tokens = [
      "https://example.com", "person@example.com", "550e8400-e29b-41d4-a716-446655440000",
      "0123456789abcdef0123456789abcdef", "user_name", "camelCase", "TLS", "abc123",
    ]
    for token in tokens {
      guard
        case .noCorrection(.unsafe) = engine.decide(
          request(
            token: token, activeLanguage: .english, explicitRule: .always, candidateKnown: true)
        )
      else {
        return XCTFail("Expected hard safety exclusion for \(token)")
      }
    }
  }

  private func request(
    token: String,
    activeLanguage: TokenLanguage,
    surface: InputSurface = .standardText,
    explicitRule: ExplicitCorrectionRule = .none,
    leadingCommandPrefix: LeadingCommandPrefix? = nil,
    originalKnown: Bool = false,
    candidateKnown: Bool = false
  ) -> CorrectionRequest {
    CorrectionRequest(
      token: token,
      activeLanguage: activeLanguage,
      surface: surface,
      explicitRule: explicitRule,
      lexiconEvidence: LexiconEvidence(
        originalIsKnown: originalKnown,
        candidateIsKnown: candidateKnown
      ),
      leadingCommandPrefix: leadingCommandPrefix
    )
  }

  private func correction(
    for request: CorrectionRequest,
    using engine: CorrectionDecisionEngine? = nil
  ) throws -> CorrectionProposal {
    guard case .correct(let proposal) = (engine ?? self.engine).decide(request) else {
      throw UnexpectedDecision()
    }
    return proposal
  }

  private struct UnexpectedDecision: Error {}
}
