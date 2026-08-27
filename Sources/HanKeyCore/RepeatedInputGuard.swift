/// Volatile, bounded intent memory. Callers must reset it when focus or protection context changes.
public struct RepeatedInputGuard: Sendable {
  public let maximumSuppressedWordCount: Int

  private var pendingDeletedCorrectionTokens: [PhysicalKeyToken]?
  private var suppressedTokenSequences: [[PhysicalKeyToken]] = []

  public init(maximumSuppressedWordCount: Int = 32) {
    precondition(maximumSuppressedWordCount > 0)
    self.maximumSuppressedWordCount = maximumSuppressedWordCount
    suppressedTokenSequences.reserveCapacity(maximumSuppressedWordCount)
  }

  public mutating func armSuppressionAfterDeletion(for word: BufferedWord) {
    pendingDeletedCorrectionTokens = word.tokens
  }

  public mutating func shouldSuppressCorrection(for word: BufferedWord) -> Bool {
    let tokens = word.tokens

    if let pendingDeletedCorrectionTokens {
      self.pendingDeletedCorrectionTokens = nil
      if pendingDeletedCorrectionTokens == tokens {
        rememberSuppressed(tokens)
        return true
      }
    }

    return suppressedTokenSequences.contains(tokens)
  }

  public mutating func cancelPendingComparison() {
    pendingDeletedCorrectionTokens = nil
  }

  public mutating func reset() {
    pendingDeletedCorrectionTokens = nil
    suppressedTokenSequences.removeAll(keepingCapacity: true)
  }

  private mutating func rememberSuppressed(_ tokens: [PhysicalKeyToken]) {
    guard !suppressedTokenSequences.contains(tokens) else {
      return
    }
    if suppressedTokenSequences.count == maximumSuppressedWordCount {
      suppressedTokenSequences.removeFirst()
    }
    suppressedTokenSequences.append(tokens)
  }
}
