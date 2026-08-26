import Foundation
import HanKeyCore

@MainActor
public final class CorrectionTransactionCoordinator {
  public typealias Delay = @MainActor @Sendable () async -> Void

  private let rewriter: any FocusedTextRewriting
  private let inputSources: any InputSourceControlling
  private let delay: Delay
  private let verificationAttempts: Int
  private var isBusy = false

  public init(
    rewriter: any FocusedTextRewriting = FocusedTextRewriter(),
    inputSources: any InputSourceControlling = InputSourceController(),
    verificationAttempts: Int = 4,
    delay: @escaping Delay = {
      try? await Task.sleep(for: .milliseconds(8))
    }
  ) {
    precondition(verificationAttempts > 0)
    self.rewriter = rewriter
    self.inputSources = inputSources
    self.verificationAttempts = verificationAttempts
    self.delay = delay
  }

  public func perform(
    proposal: CorrectionProposal,
    boundary: WordBoundary,
    expectedFocus: FocusedElementIdentity
  ) async -> CorrectionTransactionResult {
    guard !isBusy else {
      return .cancelled(.busy)
    }
    isBusy = true
    defer { isBusy = false }

    guard let sourceBefore = inputSources.currentSource() else {
      return .cancelled(.sourceUnavailable)
    }
    guard sourceBefore.language == proposal.targetLanguage.opposite else {
      return .cancelled(.sourceChanged)
    }

    await delay()
    guard let snapshot = rewriter.currentSnapshot() else {
      return .cancelled(.selectionUnavailable)
    }
    guard snapshot.identity == expectedFocus else {
      return .cancelled(.focusChanged)
    }
    guard snapshot.selection.length == 0 else {
      return .cancelled(.selectionChanged)
    }

    let originalLength = proposal.original.utf16.count
    let boundaryLength = 1
    let replacedLength = originalLength + boundaryLength
    guard snapshot.selection.location >= replacedLength else {
      return .cancelled(.selectionChanged)
    }
    let replacedRange = TextUTF16Range(
      location: snapshot.selection.location - replacedLength,
      length: replacedLength
    )
    guard let observedText = rewriter.text(in: replacedRange, matching: snapshot) else {
      return .cancelled(.selectionUnavailable)
    }
    guard
      let boundaryText = validatedBoundary(
        in: observedText,
        original: proposal.original,
        boundary: boundary
      )
    else {
      return .cancelled(.textMismatch)
    }

    let replacementWithBoundary = proposal.replacement + boundaryText
    guard
      rewriter.replace(
        range: replacedRange,
        with: replacementWithBoundary,
        matching: snapshot
      )
    else {
      return .cancelled(.replacementRejected)
    }

    let expectedCaret = replacedRange.location + replacementWithBoundary.utf16.count
    guard await verifyCaret(identity: expectedFocus, location: expectedCaret) else {
      await rollbackIfPresent(
        identity: expectedFocus,
        originalWithBoundary: observedText,
        replacementWithBoundary: replacementWithBoundary
      )
      return .cancelled(.replacementUnverified)
    }

    let provisionalRecord = CorrectionTransactionRecord(
      focusIdentity: expectedFocus,
      originalWithBoundary: observedText,
      replacementWithBoundary: replacementWithBoundary,
      replacedRange: replacedRange,
      sourceBefore: sourceBefore,
      sourceAfter: nil
    )
    guard let sourceAfter = inputSources.select(language: proposal.targetLanguage) else {
      return .cancelled(.sourceSwitchFailed(provisionalRecord))
    }
    return .corrected(
      CorrectionTransactionRecord(
        focusIdentity: expectedFocus,
        originalWithBoundary: observedText,
        replacementWithBoundary: replacementWithBoundary,
        replacedRange: replacedRange,
        sourceBefore: sourceBefore,
        sourceAfter: sourceAfter
      )
    )
  }

  private func verifyCaret(identity: FocusedElementIdentity, location: Int) async -> Bool {
    for _ in 0..<verificationAttempts {
      await delay()
      guard let snapshot = rewriter.currentSnapshot(), snapshot.identity == identity else {
        return false
      }
      if snapshot.selection == TextUTF16Range(location: location, length: 0) {
        return true
      }
    }
    return false
  }

  private func rollbackIfPresent(
    identity: FocusedElementIdentity,
    originalWithBoundary: String,
    replacementWithBoundary: String
  ) async {
    guard
      let snapshot = rewriter.currentSnapshot(),
      snapshot.identity == identity,
      snapshot.selection.length == 0,
      snapshot.selection.location >= replacementWithBoundary.utf16.count
    else {
      return
    }
    let range = TextUTF16Range(
      location: snapshot.selection.location - replacementWithBoundary.utf16.count,
      length: replacementWithBoundary.utf16.count
    )
    guard rewriter.text(in: range, matching: snapshot) == replacementWithBoundary else {
      return
    }
    _ = rewriter.replace(range: range, with: originalWithBoundary, matching: snapshot)
    await delay()
  }

  private func validatedBoundary(
    in observedText: String,
    original: String,
    boundary: WordBoundary
  ) -> String? {
    guard observedText.hasPrefix(original) else {
      return nil
    }
    let suffix = String(observedText.dropFirst(original.count))
    guard suffix.utf16.count == 1 else {
      return nil
    }
    switch boundary {
    case .space:
      return suffix == " " ? suffix : nil
    case .returnKey:
      return suffix == "\n" || suffix == "\r" ? suffix : nil
    case .tab:
      return suffix == "\t" ? suffix : nil
    case .punctuation:
      return suffix.unicodeScalars.allSatisfy {
        CharacterSet.punctuationCharacters.contains($0)
      } ? suffix : nil
    }
  }
}
