import HanKeyCore
import XCTest

final class TokenSafetyClassifierTests: XCTestCase {
  private let classifier = TokenSafetyClassifier()

  func testEligibleNaturalLanguageTokens() {
    XCTAssertEqual(classifier.classify(token: "gksrmffh", surface: .standardText), .eligible)
    XCTAssertEqual(classifier.classify(token: "ㅛㅐㅜㄴ댜", surface: .standardText), .eligible)
  }

  func testProtectedSurfacesAlwaysFailClosed() {
    for surface in [
      InputSurface.browserAddressBar, .terminal, .ide, .passwordManager, .remoteDesktop,
      .secureTextField,
    ] {
      XCTAssertEqual(
        classifier.classify(token: "gksrmffh", surface: surface),
        .excluded(.protectedSurface)
      )
    }
  }

  func testAddressCodeAndRandomValuePatternsAreExcluded() {
    let cases: [(String, SafetyExclusionReason)] = [
      ("https://example.com", .networkAddressOrPath),
      ("person@example.com", .networkAddressOrPath),
      ("192.168.0.1", .networkAddressOrPath),
      ("/usr/local/bin", .networkAddressOrPath),
      ("550e8400-e29b-41d4-a716-446655440000", .uuid),
      ("0123456789abcdef0123456789abcdef", .hash),
      ("user_name", .codeIdentifier),
      ("camelCase", .codeIdentifier),
      ("TLS", .allCaps),
      ("abc123", .numeric),
      ("hello!", .punctuation),
      ("abc한글", .mixedScript),
      ("aZ3pQ8mN2vK7", .numeric),
      ("qwertyuiopasdf", .highEntropy),
    ]

    for (token, reason) in cases {
      XCTAssertEqual(
        classifier.classify(token: token, surface: .standardText),
        .excluded(reason),
        token
      )
    }
  }

  func testLengthAndApplicationExclusions() {
    XCTAssertEqual(classifier.classify(token: "dk", surface: .standardText), .excluded(.tooShort))
    XCTAssertEqual(
      classifier.classify(token: String(repeating: "a", count: 65), surface: .standardText),
      .excluded(.tooLong)
    )
    XCTAssertEqual(
      classifier.classify(token: "gksrmffh", surface: .standardText, isApplicationExcluded: true),
      .excluded(.excludedApplication)
    )
  }
}
