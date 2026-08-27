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
      )
    )
  }

  private func correction(for request: CorrectionRequest) throws -> CorrectionProposal {
    guard case .correct(let proposal) = engine.decide(request) else {
      throw UnexpectedDecision()
    }
    return proposal
  }

  private struct UnexpectedDecision: Error {}
}
