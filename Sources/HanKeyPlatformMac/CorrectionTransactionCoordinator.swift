import Foundation
import HanKeyCore

@MainActor
public final class CorrectionTransactionCoordinator {
  public typealias Delay = @MainActor @Sendable () async -> Void
  public typealias ExclusionProvider = @MainActor (String?) -> Bool
  public typealias SequenceProvider = @MainActor () -> UInt64

  private let rewriter: any FocusedTextRewriting
  private let inputSources: any InputSourceControlling
  private let isApplicationExcluded: ExclusionProvider
  private let currentSequence: SequenceProvider
  private let makeInputHandoff: @MainActor () -> (any InputHandoffControlling)?
  private let delay: Delay
  private let verificationAttempts: Int
  private let punctuationSettlingAttempts: Int
  private var isBusy = false
  private static let specialBoundaryCharacters = CharacterSet.punctuationCharacters.union(.symbols)

  public init(
    rewriter: any FocusedTextRewriting = FocusedTextRewriter(),
    inputSources: any InputSourceControlling = InputSourceController(),
    isApplicationExcluded: @escaping ExclusionProvider = { _ in false },
    currentSequence: @escaping SequenceProvider = { 0 },
    makeInputHandoff: @escaping @MainActor () -> (any InputHandoffControlling)? = {
      InputHandoff()
    },
    verificationAttempts: Int = 4,
    punctuationSettlingAttempts: Int = 12,
    delay: @escaping Delay = {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) {
          continuation.resume()
        }
      }
    }
  ) {
    precondition(verificationAttempts > 0)
    precondition(punctuationSettlingAttempts > 0)
    self.rewriter = rewriter
    self.inputSources = inputSources
    self.isApplicationExcluded = isApplicationExcluded
    self.currentSequence = currentSequence
    self.makeInputHandoff = makeInputHandoff
    self.verificationAttempts = verificationAttempts
    self.punctuationSettlingAttempts = punctuationSettlingAttempts
    self.delay = delay
  }

  public func perform(
    proposal: CorrectionProposal,
    boundary: WordBoundary,
    expectedFocus: FocusedElementIdentity,
    expectedEventSequence: UInt64? = nil
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
        located: (range: TextUTF16Range, text: String, boundary: String),
        settledAmbiguousBoundary: Bool
      )?
    var observedSnapshot = false
    let locationAttempts =
      boundary == .punctuation ? punctuationSettlingAttempts : verificationAttempts
    let boundaryPolicy = BoundarySafetyPolicy()
    for attempt in 0..<locationAttempts {
      await delay()
      guard !Task.isCancelled else {
        return .cancelled(.cancelled)
      }
      if let expectedEventSequence, currentSequence() != expectedEventSequence {
        return .cancelled(.eventSequenceChanged)
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
      let requiresContinuationCheck = boundaryPolicy.requiresContinuationCheck(
        boundary: locatedText.boundary
      )
      if boundary == .questionMark || requiresContinuationCheck,
        attempt < locationAttempts - 1
      {
        continue
      }
      committedText = (snapshot, locatedText, requiresContinuationCheck)
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
      boundaryPolicy.permitsAutomaticCorrection(
        boundary: boundaryText,
        allowsNaturalQuestionMark: boundary == .questionMark,
        hasSettledAmbiguousBoundary: committedText.settledAmbiguousBoundary
      )
    else {
      return .cancelled(.unsafeBoundary)
    }
    guard !Task.isCancelled,
      expectedEventSequence.map({ currentSequence() == $0 }) ?? true
    else { return .cancelled(.eventSequenceChanged) }
    guard let handoff = makeInputHandoff() else { return .cancelled(.cancelled) }
    defer { handoff.finish() }
    let mayMutate: @MainActor () -> Bool = {
      !Task.isCancelled && handoff.isValid
        && (expectedEventSequence.map { self.currentSequence() == $0 } ?? true)
    }
    let replacementWithBoundary = proposal.replacement + boundaryText
    guard
      await rewriter.replace(
        range: replacedRange,
        with: replacementWithBoundary,
        matching: snapshot,
        isStillValid: {
          self.inputSources.currentSource() == sourceBefore && mayMutate()
        }
      )
    else {
      return .cancelled(.replacementRejected)
    }

    guard
      await rewriter.waitsForReplacement(
        replacementWithBoundary, in: replacedRange, identity: expectedFocus,
        isStillValid: mayMutate, attempts: verificationAttempts, delay: delay
      )
    else {
      // An unverified write may still be in flight. Never launch another write over it.
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
    guard mayMutate(), inputSources.currentSource() == sourceBefore else {
      return .cancelled(.sourceSwitchFailed(provisionalRecord))
    }
    let selectedSource = inputSources.select(language: proposal.targetLanguage)
    guard
      await rewriter.waitsForReplacement(
        replacementWithBoundary, in: replacedRange, identity: expectedFocus,
        isStillValid: mayMutate, attempts: verificationAttempts, delay: delay
      )
    else { return .cancelled(.replacementUnverified) }
    guard mayMutate(), let sourceAfter = selectedSource,
      inputSources.currentSource() == sourceAfter
    else { return .cancelled(.sourceSwitchFailed(provisionalRecord)) }
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
