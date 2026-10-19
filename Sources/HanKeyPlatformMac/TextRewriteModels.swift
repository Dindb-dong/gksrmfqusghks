import HanKeyCore

public struct TextUTF16Range: Equatable, Sendable {
  public let location: Int
  public let length: Int

  public init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }

  public var upperBound: Int {
    location + length
  }
}

public struct FocusedTextSnapshot: Equatable, Sendable {
  public let identity: FocusedElementIdentity
  public let selection: TextUTF16Range
  public let bundleIdentifier: String?

  public init(
    identity: FocusedElementIdentity,
    selection: TextUTF16Range,
    bundleIdentifier: String? = nil
  ) {
    self.identity = identity
    self.selection = selection
    self.bundleIdentifier = bundleIdentifier
  }
}

public struct InputSourceSnapshot: Equatable, Sendable {
  public let identifier: String
  public let language: TokenLanguage

  public init(identifier: String, language: TokenLanguage) {
    self.identifier = identifier
    self.language = language
  }
}

public struct CorrectionTransactionRecord: Equatable, Sendable {
  public let focusIdentity: FocusedElementIdentity
  public let originalWithBoundary: String
  public let replacementWithBoundary: String
  public let replacedRange: TextUTF16Range
  public let sourceBefore: InputSourceSnapshot
  public let sourceAfter: InputSourceSnapshot?
}

public enum CorrectionTransactionFailure: Equatable, Sendable {
  case busy
  case cancelled
  case sourceUnavailable
  case sourceChanged
  case eventSequenceChanged
  case focusChanged
  case applicationExcluded
  case selectionUnavailable
  case selectionChanged
  case textMismatch
  case unsafeBoundary
  case replacementRejected
  case replacementUnverified
  case sourceSwitchFailed(CorrectionTransactionRecord)
}

public enum CorrectionTransactionResult: Equatable, Sendable {
  case corrected(CorrectionTransactionRecord)
  case cancelled(CorrectionTransactionFailure)
}

@MainActor
public final class PreparedTextReplacement {
  private var operation: ((@MainActor () -> Bool) -> Bool)?

  public init(_ operation: @escaping (@MainActor () -> Bool) -> Bool) {
    self.operation = operation
  }

  public func perform(isStillValid: @MainActor () -> Bool) -> Bool {
    guard let operation else { return false }
    self.operation = nil
    return operation(isStillValid)
  }
}

@MainActor
public protocol FocusedTextRewriting: AnyObject {
  func currentSnapshot() -> FocusedTextSnapshot?
  func text(in range: TextUTF16Range, matching snapshot: FocusedTextSnapshot) -> String?
  func prepareReplacement(
    range: TextUTF16Range, with text: String, expectedText: String,
    matching snapshot: FocusedTextSnapshot
  ) -> PreparedTextReplacement?
  func replace(
    range: TextUTF16Range,
    with text: String,
    matching snapshot: FocusedTextSnapshot,
    isStillValid: @MainActor () -> Bool
  ) -> Bool
}

@MainActor
public protocol InputSourceControlling: AnyObject {
  func currentSource() -> InputSourceSnapshot?
  func select(language: TokenLanguage) -> InputSourceSnapshot?
  func selectAndConfirm(
    language: TokenLanguage, isStillValid: @MainActor () -> Bool
  ) async -> InputSourceSnapshot?
}

// Web accessibility caches acknowledge accepted mutations asynchronously.
extension FocusedTextRewriting {
  public func prepareReplacement(
    range: TextUTF16Range, with text: String, expectedText: String,
    matching snapshot: FocusedTextSnapshot
  ) -> PreparedTextReplacement? {
    guard self.text(in: range, matching: snapshot) == expectedText else { return nil }
    return PreparedTextReplacement { isStillValid in
      self.replace(range: range, with: text, matching: snapshot, isStillValid: isStillValid)
    }
  }

  func waitsForReplacement(
    _ text: String, in range: TextUTF16Range, identity: FocusedElementIdentity,
    isStillValid: @MainActor () -> Bool, attempts: Int = 4,
    delay: @MainActor () async -> Void = {
      try? await Task.sleep(for: .milliseconds(4))
    }
  ) async -> Bool {
    for attempt in 0..<attempts {
      guard !Task.isCancelled, isStillValid() else { return false }
      guard let snapshot = currentSnapshot(), snapshot.identity == identity,
        !Task.isCancelled, isStillValid()
      else { return false }
      let caret = TextUTF16Range(location: range.location + text.utf16.count, length: 0)
      if snapshot.selection == caret {
        let inserted = TextUTF16Range(location: range.location, length: text.utf16.count)
        guard let observed = self.text(in: inserted, matching: snapshot) else { return false }
        if observed == text { return !Task.isCancelled && isStillValid() }
      }
      if attempt + 1 < attempts { await delay() }
    }
    return false
  }

}
