public enum CorrectionDeletionAction: Equatable, Sendable {
  case none
  case correctionFullyDeleted(BufferedWord)
  case cancelled
}

/// Tracks caret movement around the latest correction without retaining corrected text.
public struct CorrectionDeletionTracker: Sendable {
  private var trackedWord: BufferedWord?
  private var correctionStart = 0
  private var lastCaretLocation = 0

  public private(set) var isTracking = false

  public init() {}

  public mutating func beginTracking(
    word: BufferedWord,
    correctionStart: Int,
    correctedCaretLocation: Int
  ) {
    guard correctionStart >= 0, correctedCaretLocation > correctionStart else {
      reset()
      return
    }
    trackedWord = word
    self.correctionStart = correctionStart
    lastCaretLocation = correctedCaretLocation
    isTracking = true
  }

  public mutating func observeCaret(location: Int) -> CorrectionDeletionAction {
    guard isTracking, let trackedWord else { return .none }

    if location == correctionStart {
      reset()
      return .correctionFullyDeleted(trackedWord)
    }
    guard location > correctionStart, location < lastCaretLocation else {
      reset()
      return .cancelled
    }
    lastCaretLocation = location
    return .none
  }

  public mutating func cancel() -> CorrectionDeletionAction {
    guard isTracking else { return .none }
    reset()
    return .cancelled
  }

  public mutating func reset() {
    trackedWord = nil
    correctionStart = 0
    lastCaretLocation = 0
    isTracking = false
  }
}
