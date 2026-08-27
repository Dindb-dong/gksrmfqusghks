import Foundation
import HanKeyCore

@MainActor
public final class CorrectionTransactionCoordinator {
  public typealias Delay = @MainActor @Sendable () async -> Void
  public typealias ExclusionProvider = @MainActor (String?) -> Bool

  private let rewriter: any FocusedTextRewriting
  private let inputSources: any InputSourceControlling
  private let isApplicationExcluded: ExclusionProvider
  private let delay: Delay
  private let verificationAttempts: Int
  private var isBusy = false
  private static let specialBoundaryCharacters = CharacterSet.punctuationCharacters.union(.symbols)

  public init(
    rewriter: any FocusedTextRewriting = FocusedTextRewriter(),
    inputSources: any InputSourceControlling = InputSourceController(),
    isApplicationExcluded: @escaping ExclusionProvider = { _ in false },
    verificationAttempts: Int = 4,
    delay: @escaping Delay = {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) {
          continuation.resume()
        }
      }
    }
  ) {
    precondition(verificationAttempts > 0)
    self.rewriter = rewriter
    self.inputSources = inputSources
    self.isApplicationExcluded = isApplicationExcluded
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

    var committedText:
      (
        snapshot: FocusedTextSnapshot,
        located: (range: TextUTF16Range, text: String, boundary: String)
      )?
    var observedSnapshot = false
    for attempt in 0..<verificationAttempts {
      await delay()
      guard !Task.isCancelled else {
        return .cancelled(.cancelled)
      }
      guard let snapshot = rewriter.currentSnapshot() else {
        continue
      }
      observedSnapshot = true
      guard !isApplicationExcluded(snapshot.bundleIdentifier) else {
        return .cancelled(.applicationExcluded)
      }
      guard snapshot.identity == expectedFocus else {
        return .cancelled(.focusChanged)
      }
      guard snapshot.selection.length == 0 else {
        return .cancelled(.selectionChanged)
      }
      guard
        let locatedText = locateText(
          original: proposal.original,
          boundary: boundary,
          snapshot: snapshot
        )
      else {
        continue
      }
      if boundary == .questionMark, attempt < verificationAttempts - 1 {
        continue
      }
      committedText = (snapshot, locatedText)
      break
    }
    guard let committedText else {
      return .cancelled(observedSnapshot ? .textMismatch : .selectionUnavailable)
    }
    let snapshot = committedText.snapshot
    let locatedText = committedText.located
    guard inputSources.currentSource() == sourceBefore else {
      return .cancelled(.sourceChanged)
    }

    let replacedRange = locatedText.range
    let observedText = locatedText.text
    let boundaryText = locatedText.boundary
    guard
      BoundarySafetyPolicy().permitsAutomaticCorrection(
        boundary: boundaryText,
        allowsNaturalQuestionMark: boundary == .questionMark
      )
    else {
      return .cancelled(.unsafeBoundary)
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
        replacementWithBoundary: replacementWithBoundary,
        boundaryText: boundaryText,
        replacedRange: replacedRange
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
    replacementWithBoundary: String,
    boundaryText: String,
    replacedRange: TextUTF16Range
  ) async {
    guard
      let snapshot = rewriter.currentSnapshot(),
      snapshot.identity == identity,
      snapshot.selection.length == 0,
      snapshot.selection.location > replacedRange.location,
      snapshot.selection.location
        <= replacedRange.location + replacementWithBoundary.utf16.count
    else {
      return
    }
    let range = TextUTF16Range(
      location: replacedRange.location,
      length: snapshot.selection.location - replacedRange.location
    )
    guard
      let currentText = rewriter.text(in: range, matching: snapshot),
      !currentText.isEmpty,
      replacementWithBoundary.hasPrefix(currentText)
        || (!boundaryText.isEmpty && currentText == boundaryText)
    else {
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
    switch boundary {
    case .space:
      return suffix.first == " " && suffix.allSatisfy(\.isWhitespace) ? suffix : nil
    case .returnKey:
      return suffix.isEmpty || suffix == "\n" || suffix == "\r" ? suffix : nil
    case .tab:
      return suffix.isEmpty || suffix == "\t" ? suffix : nil
    case .punctuation:
      guard
        let firstScalar = suffix.unicodeScalars.first,
        Self.specialBoundaryCharacters.contains(firstScalar)
      else {
        return nil
      }
      return suffix.unicodeScalars.dropFirst().allSatisfy {
        Self.specialBoundaryCharacters.contains($0)
          || CharacterSet.whitespacesAndNewlines.contains($0)
      } ? suffix : nil
    case .questionMark:
      guard suffix.first == "?" else {
        return nil
      }
      return suffix.unicodeScalars.dropFirst().allSatisfy {
        Self.specialBoundaryCharacters.contains($0)
          || CharacterSet.whitespacesAndNewlines.contains($0)
      } ? suffix : nil
    }
  }

  private func locateText(
    original: String,
    boundary: WordBoundary,
    snapshot: FocusedTextSnapshot
  ) -> (range: TextUTF16Range, text: String, boundary: String)? {
    let boundaryLengths: [Int]
    switch boundary {
    case .space, .punctuation, .questionMark:
      boundaryLengths = Array((1...4).reversed())
    case .returnKey, .tab:
      boundaryLengths = [1, 0]
    }
    for boundaryLength in boundaryLengths {
      let length = original.utf16.count + boundaryLength
      guard snapshot.selection.location >= length else {
        continue
      }
      let range = TextUTF16Range(
        location: snapshot.selection.location - length,
        length: length
      )
      guard
        let text = rewriter.text(in: range, matching: snapshot),
        let boundaryText = validatedBoundary(
          in: text,
          original: original,
          boundary: boundary
        )
      else {
        continue
      }
      return (range, text, boundaryText)
    }
    return nil
  }
}
