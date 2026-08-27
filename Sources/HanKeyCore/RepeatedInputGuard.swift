public struct RepeatedInputGuard: Sendable {
  public let maximumSuppressedWordCount: Int

  private var pendingCorrectedTokens: [PhysicalKeyToken]?
  private var suppressedTokenSequences: [[PhysicalKeyToken]] = []

  public init(maximumSuppressedWordCount: Int = 32) {
    precondition(maximumSuppressedWordCount > 0)
    self.maximumSuppressedWordCount = maximumSuppressedWordCount
    suppressedTokenSequences.reserveCapacity(maximumSuppressedWordCount)
  }

  public mutating func recordCorrection(for word: BufferedWord) {
    pendingCorrectedTokens = word.tokens
  }

  public mutating func shouldSuppressCorrection(for word: BufferedWord) -> Bool {
    let tokens = word.tokens

    if let pendingCorrectedTokens {
      self.pendingCorrectedTokens = nil
      if pendingCorrectedTokens == tokens {
        rememberSuppressed(tokens)
        return true
      }
    }

    return suppressedTokenSequences.contains(tokens)
  }

  public mutating func reset() {
    pendingCorrectedTokens = nil
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
