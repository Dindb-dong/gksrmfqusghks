/// Volatile, bounded intent memory. Callers must reset it when focus or protection context changes.
public struct RepeatedInputGuard: Sendable {
  public let maximumSuppressedWordCount: Int

  private var pendingDeletedCorrectionWord: BufferedWord?
  private var suppressedWords: [BufferedWord] = []

  public init(maximumSuppressedWordCount: Int = 32) {
    precondition(maximumSuppressedWordCount > 0)
    self.maximumSuppressedWordCount = maximumSuppressedWordCount
    suppressedWords.reserveCapacity(maximumSuppressedWordCount)
  }

  public mutating func armSuppressionAfterDeletion(for word: BufferedWord) {
    pendingDeletedCorrectionWord = word
  }

  public mutating func shouldSuppressCorrection(for word: BufferedWord) -> Bool {
    if let pendingDeletedCorrectionWord {
      self.pendingDeletedCorrectionWord = nil
      if pendingDeletedCorrectionWord == word {
        rememberSuppressed(word)
        return true
      }
    }

    return suppressedWords.contains(word)
  }

  public mutating func cancelPendingComparison() {
    pendingDeletedCorrectionWord = nil
  }

  public mutating func reset() {
    pendingDeletedCorrectionWord = nil
    suppressedWords.removeAll(keepingCapacity: true)
  }

  private mutating func rememberSuppressed(_ word: BufferedWord) {
    guard !suppressedWords.contains(word) else {
      return
    }
    if suppressedWords.count == maximumSuppressedWordCount {
      suppressedWords.removeFirst()
    }
    suppressedWords.append(word)
  }
}
