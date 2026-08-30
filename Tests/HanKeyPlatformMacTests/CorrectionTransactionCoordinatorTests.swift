import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class CorrectionTransactionCoordinatorTests: XCTestCase {
  private let identity = FocusedElementIdentity(processID: 42, elementHash: 7)

  func testReplacesOnlyValidatedWordAndBoundaryThenSwitchesSource() async {
    let rewriter = FakeTextRewriter(document: "앞 gksrmffh ", caret: 11, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    guard case .corrected(let record) = result else {
      return XCTFail("Expected a committed correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "앞 한글로 ")
    XCTAssertEqual(rewriter.selection, TextUTF16Range(location: 6, length: 0))
    XCTAssertEqual(sources.selectedLanguages, [.korean])
    XCTAssertEqual(record.originalWithBoundary, "gksrmffh ")
    XCTAssertEqual(record.replacementWithBoundary, "한글로 ")
    XCTAssertEqual(record.sourceBefore.language, .english)
    XCTAssertEqual(record.sourceAfter?.language, .korean)
  }

  func testLeadingSlashIsPreservedWhileOnlyCommandBodyIsReplaced() async {
    let original = "채ㅡㅔㅁㅊㅅ"
    let rewriter = FakeTextRewriter(document: "/\(original) ", caret: 8, identity: identity)
    let sources = FakeInputSources(currentLanguage: .korean)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: original, replacement: "compact", target: .english),
      boundary: .space,
      expectedFocus: identity
    )

    guard case .corrected(let record) = result else {
      return XCTFail("Expected a committed command correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "/compact ")
    XCTAssertEqual(record.replacedRange.location, 1)
    XCTAssertEqual(sources.selectedLanguages, [.english])
  }

  func testRetriesUntilSpaceCommitBecomesVisibleThroughAccessibility() async {
    let original = "채ㅡㅔㅁㅊㅅ"
    let rewriter = FakeTextRewriter(document: "/\(original)", caret: 7, identity: identity)
    let sources = FakeInputSources(currentLanguage: .korean)
    var delayCount = 0
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      verificationAttempts: 4,
      delay: {
        delayCount += 1
        if delayCount == 2 {
          rewriter.document.append(" ")
          rewriter.selection = TextUTF16Range(location: 8, length: 0)
        }
      }
    )

    let result = await coordinator.perform(
      proposal: proposal(original: original, replacement: "compact", target: .english),
      boundary: .space,
      expectedFocus: identity
    )

    guard case .corrected = result else {
      return XCTFail("Expected delayed Space commit to be retried, got \(result)")
    }
    XCTAssertGreaterThanOrEqual(delayCount, 2)
    XCTAssertEqual(rewriter.document, "/compact ")
    XCTAssertEqual(sources.selectedLanguages, [.english])
  }

  func testInputSourceChangeDuringSpaceSettlingCancelsBeforeMutation() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      verificationAttempts: 4,
      delay: {
        sources.current = InputSourceSnapshot(
          identifier: InputSourceController.korean2SetIdentifier,
          language: .korean
        )
      }
    )

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.sourceChanged))
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testPreservesObservedPunctuationInsteadOfSynthesizingIt() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh,", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .punctuation,
      expectedFocus: identity
    )

    guard case .corrected = result else {
      return XCTFail("Expected a committed correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "한글로,")
  }

  func testNaturalQuestionMarkIsPreservedDuringCorrection() async {
    let rewriter = FakeTextRewriter(document: "좀ㅅ?", caret: 3, identity: identity)
    let sources = FakeInputSources(currentLanguage: .korean)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "좀ㅅ", replacement: "what", target: .english),
      boundary: .questionMark,
      expectedFocus: identity
    )

    guard case .corrected = result else {
      return XCTFail("Expected a natural question to correct, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "what?")
    XCTAssertEqual(sources.selectedLanguages, [.english])
  }

  func testQuestionMarkWaitsForRapidQueryContinuationAndFailsClosed() async {
    let rewriter = FakeTextRewriter(document: "좀ㅅ?", caret: 3, identity: identity)
    let sources = FakeInputSources(currentLanguage: .korean)
    var delayCount = 0
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      verificationAttempts: 4,
      delay: {
        delayCount += 1
        if delayCount == 2 {
          rewriter.document += "a"
          rewriter.selection = TextUTF16Range(location: 4, length: 0)
        }
      }
    )

    let result = await coordinator.perform(
      proposal: proposal(original: "좀ㅅ", replacement: "what", target: .english),
      boundary: .questionMark,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.textMismatch))
    XCTAssertEqual(rewriter.document, "좀ㅅ?a")
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testPreservesRapidPunctuationClusterAndTrailingSpace() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh!! ", caret: 11, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .punctuation,
      expectedFocus: identity
    )

    guard case .corrected = result else {
      return XCTFail("Expected a committed correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "한글로!! ")
  }

  func testPreservesEverySpecialSymbolBoundary() async {
    let symbols = [
      "~", "`", "!", "#", "$", "%", "^", "&", "*", "(", ")", "-", "_", "=", "+", "[", "{",
      "]", "}", "|", ";", ":", "'", "\"", ",", "<", ">", "§", "±", "¥",
      "©", "™", "€", "√", "∞", "•", "…",
    ]

    for symbol in symbols {
      let original = "gksrmffh\(symbol) "
      let rewriter = FakeTextRewriter(
        document: original,
        caret: original.utf16.count,
        identity: identity
      )
      let sources = FakeInputSources(currentLanguage: .english)
      let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

      let result = await coordinator.perform(
        proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
        boundary: .punctuation,
        expectedFocus: identity
      )

      guard case .corrected = result else {
        return XCTFail("Expected \(symbol) to be preserved, got \(result)")
      }
      XCTAssertEqual(rewriter.document, "한글로\(symbol) ")
    }
  }

  func testCorrectsTheSegmentBeforeUnderscoreAndHyphen() async {
    let original = "ㅁㅊㅁㅇ드ㅑㅊ"
    for separator in ["_", "-"] {
      let document = original + separator
      let rewriter = FakeTextRewriter(
        document: document,
        caret: document.utf16.count,
        identity: identity
      )
      let sources = FakeInputSources(currentLanguage: .korean)
      let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

      let result = await coordinator.perform(
        proposal: proposal(original: original, replacement: "academic", target: .english),
        boundary: .punctuation,
        expectedFocus: identity
      )

      guard case .corrected = result else {
        return XCTFail("Expected the segment before \(separator) to correct, got \(result)")
      }
      XCTAssertEqual(rewriter.document, "academic\(separator)")
      XCTAssertEqual(sources.selectedLanguages, [.english])
    }
  }

  func testAddressPathAndQueryBoundariesFailClosedEvenForProposal() async {
    for symbol in ["@", "/", "\\", ".", "?"] {
      let original = "gksrmffh\(symbol)"
      let rewriter = FakeTextRewriter(
        document: original,
        caret: original.utf16.count,
        identity: identity
      )
      let sources = FakeInputSources(currentLanguage: .english)
      let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

      let result = await coordinator.perform(
        proposal: CorrectionProposal(
          original: "gksrmffh",
          replacement: "한글로",
          targetLanguage: .korean,
          confidence: 1,
          usedExplicitRule: true
        ),
        boundary: .punctuation,
        expectedFocus: identity
      )

      XCTAssertEqual(result, .cancelled(.unsafeBoundary), symbol)
      XCTAssertEqual(rewriter.document, original, symbol)
      XCTAssertEqual(rewriter.replaceCount, 0, symbol)
      XCTAssertTrue(sources.selectedLanguages.isEmpty, symbol)
    }
  }

  func testPreservesRapidRepeatedSpaces() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh  ", caret: 10, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    guard case .corrected = result else {
      return XCTFail("Expected a committed correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "한글로  ")
  }

  func testPrintableTextAfterPunctuationFailsClosed() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh? a", caret: 11, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .punctuation,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.textMismatch))
    XCTAssertEqual(rewriter.document, "gksrmffh? a")
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testSingleLineReturnCanCommitWithoutAnInsertedBoundaryCharacter() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh", caret: 8, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .returnKey,
      expectedFocus: identity
    )

    guard case .corrected = result else {
      return XCTFail("Expected a committed correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "한글로")
    XCTAssertEqual(rewriter.selection, TextUTF16Range(location: 3, length: 0))
  }

  func testFocusRaceCancelsWithoutReadingOrMutatingText() async {
    let changedIdentity = FocusedElementIdentity(processID: 42, elementHash: 8)
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: changedIdentity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.focusChanged))
    XCTAssertEqual(rewriter.document, "gksrmffh ")
    XCTAssertEqual(rewriter.readCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testApplicationExclusionIsRevalidatedImmediatelyBeforeTextRead() async {
    let rewriter = FakeTextRewriter(
      document: "gksrmffh ",
      caret: 9,
      identity: identity,
      bundleIdentifier: "com.example.PrivateEditor"
    )
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      isApplicationExcluded: { $0 == "com.example.PrivateEditor" },
      verificationAttempts: 1,
      delay: {}
    )

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.applicationExcluded))
    XCTAssertEqual(rewriter.readCount, 0)
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testTextMismatchCancelsBeforeMutationAndSourceSelection() async {
    let rewriter = FakeTextRewriter(document: "password ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.textMismatch))
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testSourceFailureReturnsUndoableRecordAfterVerifiedRewrite() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english, canSelect: false)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    guard case .cancelled(.sourceSwitchFailed(let record)) = result else {
      return XCTFail("Expected a source switch failure with a record, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "한글로 ")
    XCTAssertEqual(record.originalWithBoundary, "gksrmffh ")
    XCTAssertNil(record.sourceAfter)
  }

  func testUnverifiedReplacementRollsBackWhenReplacementIsStillAdjacent() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.verificationFailuresRemaining = 1
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(rewriter.document, "gksrmffh ")
    XCTAssertEqual(rewriter.replaceCount, 2)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testPartiallyInsertedReplacementRollsBackFromOriginalRange() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.firstReplacementOverride = " "
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(rewriter.document, "gksrmffh ")
    XCTAssertEqual(rewriter.replaceCount, 2)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testInteriorReplacementSubstringIsNotRolledBack() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.firstReplacementOverride = "글"
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space,
      expectedFocus: identity
    )

    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(rewriter.document, "글")
    XCTAssertEqual(rewriter.replaceCount, 1)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  private func makeCoordinator(
    rewriter: FakeTextRewriter,
    sources: FakeInputSources
  ) -> CorrectionTransactionCoordinator {
    CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      verificationAttempts: 1,
      delay: {}
    )
  }

  private func proposal(
    original: String,
    replacement: String,
    target: TokenLanguage
  ) -> CorrectionProposal {
    CorrectionProposal(
      original: original,
      replacement: replacement,
      targetLanguage: target,
      confidence: 1,
      usedExplicitRule: false
    )
  }
}

@MainActor
private final class FakeTextRewriter: FocusedTextRewriting {
  var document: String
  var selection: TextUTF16Range
  var identity: FocusedElementIdentity
  var bundleIdentifier: String?
  private(set) var readCount = 0
  private(set) var replaceCount = 0
  var verificationFailuresRemaining = 0
  var firstReplacementOverride: String?
  private var replacementPerformed = false

  init(
    document: String,
    caret: Int,
    identity: FocusedElementIdentity,
    bundleIdentifier: String? = nil
  ) {
    self.document = document
    selection = TextUTF16Range(location: caret, length: 0)
    self.identity = identity
    self.bundleIdentifier = bundleIdentifier
  }

  func currentSnapshot() -> FocusedTextSnapshot? {
    if replacementPerformed, verificationFailuresRemaining > 0 {
      verificationFailuresRemaining -= 1
      return FocusedTextSnapshot(
        identity: identity,
        selection: TextUTF16Range(location: selection.location + 1, length: selection.length),
        bundleIdentifier: bundleIdentifier
      )
    }
    return FocusedTextSnapshot(
      identity: identity,
      selection: selection,
      bundleIdentifier: bundleIdentifier
    )
  }

  func text(in range: TextUTF16Range, matching snapshot: FocusedTextSnapshot) -> String? {
    readCount += 1
    guard snapshot.identity == identity else {
      return nil
    }
    let value = document as NSString
    guard range.location >= 0, range.upperBound <= value.length else {
      return nil
    }
    return value.substring(with: NSRange(location: range.location, length: range.length))
  }

  func replace(
    range: TextUTF16Range,
    with text: String,
    matching snapshot: FocusedTextSnapshot
  ) -> Bool {
    replaceCount += 1
    guard snapshot.identity == identity else {
      return false
    }
    let value = NSMutableString(string: document)
    guard range.location >= 0, range.upperBound <= value.length else {
      return false
    }
    let replacement = replaceCount == 1 ? firstReplacementOverride ?? text : text
    value.replaceCharacters(
      in: NSRange(location: range.location, length: range.length),
      with: replacement
    )
    document = value as String
    selection = TextUTF16Range(location: range.location + replacement.utf16.count, length: 0)
    replacementPerformed = true
    return true
  }
}

@MainActor
private final class FakeInputSources: InputSourceControlling {
  var current: InputSourceSnapshot?
  let canSelect: Bool
  private(set) var selectedLanguages: [TokenLanguage] = []

  init(currentLanguage: TokenLanguage, canSelect: Bool = true) {
    current = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: currentLanguage),
      language: currentLanguage
    )
    self.canSelect = canSelect
  }

  func currentSource() -> InputSourceSnapshot? {
    current
  }

  func select(language: TokenLanguage) -> InputSourceSnapshot? {
    selectedLanguages.append(language)
    guard canSelect else {
      return nil
    }
    let snapshot = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: language),
      language: language
    )
    current = snapshot
    return snapshot
  }
}
