import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class CorrectionTransactionCoordinatorTests: XCTestCase {
  private let identity = FocusedElementIdentity(processID: 42, elementHash: 7)

  func testUnsupportedSourceSwitchCancelsBeforeTextSelectionOrReplacement() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.onPrepare = { XCTFail("Must preflight before preparing text selection") }
    let sources = InputSourceController(
      readSource: {
        InputSourceSnapshot(identifier: InputSourceController.abcIdentifier, language: .english)
      },
      selectSource: { _ in
        XCTFail("No TIS fallback")
        return false
      },
      prepareNativeSwitch: { nil })
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources,
      makeInputHandoff: {
        XCTFail("No input wait for unsupported switch")
        return TestInputHandoff()
      }, delay: {})
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    XCTAssertEqual(result, .cancelled(.sourceUnavailable))
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertEqual(rewriter.document, "gksrmffh ")
  }

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
      makeInputHandoff: { TestInputHandoff() },
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
      makeInputHandoff: { TestInputHandoff() },
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
      makeInputHandoff: { TestInputHandoff() },
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

  func testAmbiguousSpecialCharactersCorrectAfterSettlingWithoutContinuation() async {
    let cases: [(symbol: String, boundary: WordBoundary)] = [
      ("@", .punctuation), ("/", .punctuation), ("\\", .punctuation),
      (".", .punctuation), ("?", .questionMark),
    ]
    for testCase in cases {
      let original = "gksrmffh\(testCase.symbol)"
      let rewriter = FakeTextRewriter(
        document: original,
        caret: original.utf16.count,
        identity: identity
      )
      let sources = FakeInputSources(currentLanguage: .english)
      let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

      let result = await coordinator.perform(
        proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
        boundary: testCase.boundary,
        expectedFocus: identity
      )

      guard case .corrected = result else {
        return XCTFail("Expected \(testCase.symbol) to correct after settling, got \(result)")
      }
      XCTAssertEqual(rewriter.document, "한글로\(testCase.symbol)")
      XCTAssertEqual(sources.selectedLanguages, [.korean])
    }
  }

  func testAmbiguousSpecialCharacterContinuationCancelsBeforeMutation() async {
    let cases: [(symbol: String, boundary: WordBoundary)] = [
      ("@", .punctuation), ("/", .punctuation), ("\\", .punctuation),
      (".", .punctuation), ("?", .questionMark),
    ]
    for testCase in cases {
      let original = "gksrmffh\(testCase.symbol)"
      let rewriter = FakeTextRewriter(
        document: original,
        caret: original.utf16.count,
        identity: identity
      )
      let sources = FakeInputSources(currentLanguage: .english)
      var delayCount = 0
      let coordinator = CorrectionTransactionCoordinator(
        rewriter: rewriter,
        inputSources: sources,
        makeInputHandoff: { TestInputHandoff() },
        verificationAttempts: 4,
        punctuationSettlingAttempts: 12,
        delay: {
          delayCount += 1
          if delayCount == 2 {
            rewriter.document.append("a")
            rewriter.selection = TextUTF16Range(
              location: rewriter.document.utf16.count,
              length: 0
            )
          }
        }
      )

      let result = await coordinator.perform(
        proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
        boundary: testCase.boundary,
        expectedFocus: identity
      )

      XCTAssertEqual(result, .cancelled(.textMismatch), testCase.symbol)
      XCTAssertEqual(rewriter.document, "\(original)a", testCase.symbol)
      XCTAssertEqual(rewriter.replaceCount, 0, testCase.symbol)
      XCTAssertTrue(sources.selectedLanguages.isEmpty, testCase.symbol)
    }
  }

  func testPhysicalInputSequenceChangeCancelsBeforeReadingOrMutation() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh\"", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    var sequence: UInt64 = 10
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      currentSequence: { sequence },
      makeInputHandoff: { TestInputHandoff() },
      verificationAttempts: 4,
      punctuationSettlingAttempts: 12,
      delay: { sequence = 11 }
    )

    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .punctuation,
      expectedFocus: identity,
      expectedEventSequence: 10
    )

    XCTAssertEqual(result, .cancelled(.eventSequenceChanged))
    XCTAssertEqual(rewriter.readCount, 0)
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testDelayedStraightAndSmartDoubleQuotesArePreserved() async {
    for quote in ["\"", "“", "”", "„", "«", "»"] {
      let original = "gksrmffh"
      let rewriter = FakeTextRewriter(
        document: original,
        caret: original.utf16.count,
        identity: identity
      )
      let sources = FakeInputSources(currentLanguage: .english)
      var delayCount = 0
      let coordinator = CorrectionTransactionCoordinator(
        rewriter: rewriter,
        inputSources: sources,
        makeInputHandoff: { TestInputHandoff() },
        verificationAttempts: 4,
        punctuationSettlingAttempts: 12,
        delay: {
          delayCount += 1
          if delayCount == 9 {
            rewriter.document.append(quote)
            rewriter.selection = TextUTF16Range(
              location: rewriter.document.utf16.count,
              length: 0
            )
          }
        }
      )

      let result = await coordinator.perform(
        proposal: proposal(original: original, replacement: "한글로", target: .korean),
        boundary: .punctuation,
        expectedFocus: identity
      )

      guard case .corrected = result else {
        return XCTFail("Expected delayed quote \(quote) to correct, got \(result)")
      }
      XCTAssertEqual(rewriter.document, "한글로\(quote)")
      XCTAssertEqual(sources.selectedLanguages, [.korean])
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
      makeInputHandoff: { TestInputHandoff() },
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

  func testNativeSwitchStillRunsAfterCostlyReplacementAcknowledgment() async throws {
    for target in [TokenLanguage.korean, .english] {
      let original = target == .korean ? "gksrmffh" : "ㅡ먀ㅜ"
      let replacement = target == .korean ? "한글로" : "main"
      let rewriter = FakeTextRewriter(
        document: original + " ", caret: original.utf16.count + 1, identity: identity)
      let handoff = TimedInputHandoff()
      let center = NotificationCenter()
      var source = InputSourceSnapshot(
        identifier: InputSourceController.identifier(for: target.opposite),
        language: target.opposite)
      let sources = InputSourceController(
        readSource: { source },
        selectSource: { _ in
          XCTFail("Native path fell back to TIS")
          return false
        },
        prepareNativeSwitch: { NativeInputSourceSwitch() }, notifications: center,
        acknowledgmentDelay: {})
      handoff.onCommand = {
        source = InputSourceSnapshot(
          identifier: InputSourceController.identifier(for: target), language: target)
        center.post(name: InputSourceController.sourceChanged, object: nil)
      }
      rewriter.onReplace = {
        handoff.advance(milliseconds: 40)
        rewriter.onRead = { handoff.advance(milliseconds: 20) }
      }
      let coordinator = CorrectionTransactionCoordinator(
        rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff }, delay: {})
      let result = await coordinator.perform(
        proposal: proposal(original: original, replacement: replacement, target: target),
        boundary: .space, expectedFocus: identity)
      guard case .corrected(let record) = result else {
        XCTFail("Verified replacement must retain a native source-switch budget: \(result)")
        continue
      }
      XCTAssertEqual(record.sourceAfter?.language, target)
      XCTAssertEqual(InputHandoffDiagnostics.snapshot.outcome, .completed)
      XCTAssertEqual(handoff.commandCount, 1)
      XCTAssertEqual(rewriter.replaceCount, 1)
      XCTAssertEqual(rewriter.document, replacement + " ")
    }
  }

  func testPostSourceVerificationPreservesNativeDispatchFailure() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let handoff = TimedInputHandoff()
    handoff.onCommand = { handoff.finish() }
    let sources = InputSourceController(
      readSource: {
        InputSourceSnapshot(identifier: InputSourceController.abcIdentifier, language: .english)
      },
      selectSource: { _ in
        XCTFail("Unexpected TIS fallback")
        return false
      },
      prepareNativeSwitch: { NativeInputSourceSwitch() }, notifications: NotificationCenter(),
      acknowledgmentDelay: {})
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff }, delay: {})
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(InputHandoffDiagnostics.snapshot.outcome, .nativeDispatchFailed)
    XCTAssertEqual(InputHandoffDiagnostics.snapshot.stage, .nativeReleased)
    XCTAssertEqual(handoff.commandCount, 1)
    XCTAssertEqual(rewriter.replaceCount, 1)
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
    XCTAssertEqual(InputHandoffDiagnostics.snapshot.outcome, .cancelled)
    XCTAssertEqual(rewriter.document, "한글로 ")
    XCTAssertEqual(record.originalWithBoundary, "gksrmffh ")
    XCTAssertNil(record.sourceAfter)
  }

  func testUnverifiedReplacementDoesNotLaunchAnotherWrite() async {
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
    XCTAssertEqual(rewriter.document, "한글로 ")
    XCTAssertEqual(rewriter.replaceCount, 1)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testPartiallyInsertedReplacementDoesNotLaunchAnotherWrite() async {
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
    XCTAssertEqual(rewriter.document, " ")
    XCTAssertEqual(rewriter.replaceCount, 1)
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

  func testWrongTextAtExpectedCaretIsNotSuccessful() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.firstReplacementOverride = "다른말 "
    let sources = FakeInputSources(currentLanguage: .english)
    let result = await makeCoordinator(rewriter: rewriter, sources: sources).perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity
    )
    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(rewriter.replaceCount, 1)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testActivityDuringFinalTextReadCancelsBeforeMutation() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    var sequence: UInt64 = 1
    rewriter.onRead = { sequence = 2 }
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, currentSequence: { sequence },
      makeInputHandoff: { TestInputHandoff() }, delay: {}
    )
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity, expectedEventSequence: 1
    )
    XCTAssertEqual(result, .cancelled(.eventSequenceChanged))
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testUnavailableHandoffCancelsBeforeMutation() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { nil }, delay: {}
    )
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity
    )
    XCTAssertEqual(result, .cancelled(.cancelled))
    XCTAssertEqual(rewriter.replaceCount, 0)
  }

  func testSourceReadbackMismatchRetainsFailureRecord() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    sources.updatesCurrentSource = false
    let result = await makeCoordinator(rewriter: rewriter, sources: sources).perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity
    )
    guard case .cancelled(.sourceSwitchFailed(let record)) = result else {
      return XCTFail("Expected failed source verification")
    }
    XCTAssertNil(record.sourceAfter)
    XCTAssertEqual(rewriter.document, "한글로 ")
    XCTAssertEqual(rewriter.replaceCount, 1)
  }

  func testHandoffInvalidatedDuringVerificationDoesNotSwitchSource() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let handoff = TestInputHandoff()
    rewriter.onReplace = { rewriter.onRead = { handoff.isValid = false } }
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff }, delay: {})
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    guard case .cancelled(.replacementUnverified) = result else {
      return XCTFail("Expected interrupted handoff")
    }
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
    XCTAssertEqual(handoff.finishCount, 1)
  }

  func testHandoffInvalidatedInsideSourceSelectionIsNotSuccessful() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    let handoff = TestInputHandoff()
    sources.onSelect = { handoff.isValid = false }
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff }, delay: {})
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    guard case .cancelled(.replacementUnverified) = result else {
      return XCTFail("Expected interrupted handoff")
    }
    XCTAssertEqual(handoff.finishCount, 1)
  }

  func testSourceActivationChangingTextCannotCountAsCorrection() async {
    let rewriter = FakeTextRewriter(document: "ㅡ먀ㅜ ", caret: 4, identity: identity)
    let sources = FakeInputSources(currentLanguage: .korean)
    sources.onSelect = { rewriter.document = "mmain " }
    sources.updatesCurrentSource = false
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)
    let result = await coordinator.perform(
      proposal: proposal(original: "ㅡ먀ㅜ", replacement: "main", target: .english),
      boundary: .space, expectedFocus: identity)
    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(InputHandoffDiagnostics.snapshot.outcome, .replacementUnverified)
    XCTAssertEqual(rewriter.replaceCount, 1)
  }

  func testDelayedReplacementAcknowledgmentWritesOnlyOnce() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.verificationFailuresRemaining = 2
    let sources = FakeInputSources(currentLanguage: .english)
    let handoff = TestInputHandoff()
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff }, delay: {})
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    guard case .corrected = result else { return XCTFail("Expected delayed acknowledgment") }
    XCTAssertEqual(rewriter.replaceCount, 1)
    XCTAssertEqual(sources.selectedLanguages, [.korean])
    XCTAssertEqual(handoff.finishCount, 1)
  }

  func testFocusLossDuringAcknowledgmentPermanentlyCancels() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    rewriter.verificationFailuresRemaining = 1
    let sources = FakeInputSources(currentLanguage: .english)
    let handoff = TestInputHandoff()
    var acknowledgmentDelays = 0
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff },
      delay: {
        if rewriter.replaceCount > 0 {
          acknowledgmentDelays += 1
          rewriter.identity = FocusedElementIdentity(processID: 999, elementHash: 999)
        }
      })
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(acknowledgmentDelays, 1)
    XCTAssertEqual(rewriter.replaceCount, 1)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
    XCTAssertEqual(handoff.finishCount, 1)
  }

  func testPreparationPrecedesGateAndSourceAcknowledgmentPrecedesReleaseBothDirections() async {
    for (original, replacement, target) in [
      ("gksrmffh", "한글로", TokenLanguage.korean),
      ("ㅡ먀ㅜ", "main", TokenLanguage.english),
    ] {
      let rewriter = FakeTextRewriter(
        document: original + " ", caret: original.utf16.count + 1, identity: identity)
      rewriter.verificationFailuresRemaining = 2
      let sources = FakeInputSources(currentLanguage: target.opposite)
      let handoff = TestInputHandoff()
      var gateStarted = false
      var prepared = false
      var confirmed = false
      rewriter.onPrepare = {
        XCTAssertFalse(gateStarted)
        prepared = true
      }
      rewriter.onReplace = {
        XCTAssertTrue(prepared)
        XCTAssertTrue(gateStarted)
        XCTAssertEqual(handoff.finishCount, 0)
      }
      sources.onConfirm = {
        await Task.yield()
        XCTAssertEqual(rewriter.document, replacement + " ")
        XCTAssertEqual(rewriter.replaceCount, 1)
        XCTAssertTrue(handoff.isValid)
        XCTAssertEqual(handoff.finishCount, 0)
        confirmed = true
      }
      let coordinator = CorrectionTransactionCoordinator(
        rewriter: rewriter, inputSources: sources,
        makeInputHandoff: {
          gateStarted = true
          return handoff
        }, delay: {})
      let result = await coordinator.perform(
        proposal: proposal(original: original, replacement: replacement, target: target),
        boundary: .space, expectedFocus: identity)
      guard case .corrected = result else { return XCTFail("Expected complete handoff") }
      XCTAssertTrue(confirmed)
      XCTAssertEqual(rewriter.replaceCount, 1)
      XCTAssertEqual(handoff.finishCount, 1)
    }
  }

  func testSameLengthTextChangeBeforePreparationNeverSelectsOrStartsGate() async {
    let rewriter = FakeTextRewriter(document: "gksrmffh ", caret: 9, identity: identity)
    let sources = FakeInputSources(currentLanguage: .english)
    var gateStarted = false
    rewriter.onPrepare = { rewriter.document = "changed! " }
    let coordinator = CorrectionTransactionCoordinator(
      rewriter: rewriter, inputSources: sources,
      makeInputHandoff: {
        gateStarted = true
        return TestInputHandoff()
      }, delay: {})
    let result = await coordinator.perform(
      proposal: proposal(original: "gksrmffh", replacement: "한글로", target: .korean),
      boundary: .space, expectedFocus: identity)
    XCTAssertEqual(result, .cancelled(.replacementRejected))
    XCTAssertEqual(rewriter.replaceCount, 0)
    XCTAssertFalse(gateStarted)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  private func makeCoordinator(
    rewriter: FakeTextRewriter,
    sources: FakeInputSources
  ) -> CorrectionTransactionCoordinator {
    CorrectionTransactionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      makeInputHandoff: { TestInputHandoff() },
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
  var onRead: (() -> Void)?
  var onPrepare: (() -> Void)?
  var onReplace: (() -> Void)?
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
    onRead?()
    guard snapshot.identity == identity else {
      return nil
    }
    let value = document as NSString
    guard range.location >= 0, range.upperBound <= value.length else {
      return nil
    }
    return value.substring(with: NSRange(location: range.location, length: range.length))
  }

  func prepareReplacement(
    range: TextUTF16Range, with text: String, expectedText: String,
    matching snapshot: FocusedTextSnapshot
  ) -> PreparedTextReplacement? {
    onPrepare?()
    guard self.text(in: range, matching: snapshot) == expectedText else { return nil }
    return PreparedTextReplacement { valid in
      self.replace(range: range, with: text, matching: snapshot, isStillValid: valid)
    }
  }

  func replace(
    range: TextUTF16Range,
    with text: String,
    matching snapshot: FocusedTextSnapshot,
    isStillValid: @MainActor () -> Bool
  ) -> Bool {
    guard isStillValid() else { return false }
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
    onReplace?()
    return true
  }
}

@MainActor
private final class FakeInputSources: InputSourceControlling {
  var current: InputSourceSnapshot?
  let canSelect: Bool
  var updatesCurrentSource = true
  var onSelect: (() -> Void)?
  var onConfirm: (() async -> Void)?
  private(set) var selectedLanguages: [TokenLanguage] = []

  init(currentLanguage: TokenLanguage, canSelect: Bool = true) {
    current = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: currentLanguage),
      language: currentLanguage
    )
    self.canSelect = canSelect
  }

  func selectAndConfirm(
    language: TokenLanguage, isStillValid: @MainActor () -> Bool
  ) async -> InputSourceSnapshot? {
    guard isStillValid() else { return nil }
    let result = select(language: language)
    await onConfirm?()
    return result
  }

  func currentSource() -> InputSourceSnapshot? {
    current
  }

  func select(language: TokenLanguage) -> InputSourceSnapshot? {
    selectedLanguages.append(language)
    onSelect?()
    guard canSelect else {
      return nil
    }
    let snapshot = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: language),
      language: language
    )
    if updatesCurrentSource { current = snapshot }
    return snapshot
  }
}
