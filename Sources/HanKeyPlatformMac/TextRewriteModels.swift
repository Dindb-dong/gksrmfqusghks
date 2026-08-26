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
  case focusChanged
  case applicationExcluded
  case selectionUnavailable
  case selectionChanged
  case textMismatch
  case replacementRejected
  case replacementUnverified
  case sourceSwitchFailed(CorrectionTransactionRecord)
}

public enum CorrectionTransactionResult: Equatable, Sendable {
  case corrected(CorrectionTransactionRecord)
  case cancelled(CorrectionTransactionFailure)
}

@MainActor
public protocol FocusedTextRewriting: AnyObject {
  func currentSnapshot() -> FocusedTextSnapshot?
  func text(in range: TextUTF16Range, matching snapshot: FocusedTextSnapshot) -> String?
  func replace(
    range: TextUTF16Range,
    with text: String,
    matching snapshot: FocusedTextSnapshot
  ) -> Bool
}

@MainActor
public protocol InputSourceControlling: AnyObject {
  func currentSource() -> InputSourceSnapshot?
  func select(language: TokenLanguage) -> InputSourceSnapshot?
}
