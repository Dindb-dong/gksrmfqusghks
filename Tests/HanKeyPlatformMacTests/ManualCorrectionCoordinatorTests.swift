import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class ManualCorrectionCoordinatorTests: XCTestCase {
  private let identity = FocusedElementIdentity(processID: 7, elementHash: 9)

  func testConvertsSelectedHangulAndSwitchesToEnglish() async {
    let rewriter = ManualFakeRewriter(
      document: "앞 ㅛㅐㅜㄴ댜 뒤",
      selection: TextUTF16Range(location: 2, length: 5),
      identity: identity
    )
    let sources = ManualFakeSources(language: .korean)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.convertSelectionOrLastWord()

    guard case .corrected(let record) = result else {
      return XCTFail("Expected correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "앞 yonsei 뒤")
    XCTAssertEqual(sources.current?.language, .english)
    XCTAssertEqual(record.originalWithBoundary, "ㅛㅐㅜㄴ댜")
  }

  func testConvertsOnlyLastWordAtCaret() async {
    let rewriter = ManualFakeRewriter(
      document: "앞 gksrmffh",
      selection: TextUTF16Range(location: 10, length: 0),
      identity: identity
    )
    let sources = ManualFakeSources(language: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.convertSelectionOrLastWord()

    guard case .corrected = result else {
      return XCTFail("Expected correction, got \(result)")
    }
    XCTAssertEqual(rewriter.document, "앞 한글로")
    XCTAssertEqual(sources.current?.language, .korean)
  }

  func testUndoRequiresSameFocusCaretAndReplacement() async {
    let rewriter = ManualFakeRewriter(
      document: "gksrmffh",
      selection: TextUTF16Range(location: 8, length: 0),
      identity: identity
    )
    let sources = ManualFakeSources(language: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)
    guard case .corrected(let record) = await coordinator.convertSelectionOrLastWord() else {
      return XCTFail("Expected initial correction")
    }

    let undoResult = await coordinator.undo(record)
    XCTAssertEqual(undoResult, .undone)
    XCTAssertEqual(rewriter.document, "gksrmffh")
    XCTAssertEqual(sources.current?.language, .english)

    rewriter.document = "다른내용"
    let repeatedUndoResult = await coordinator.undo(record)
    XCTAssertEqual(repeatedUndoResult, .contextChanged)
  }

  func testMixedOrOversizedSelectionFailsClosed() async {
    let rewriter = ManualFakeRewriter(
      document: "abc한글",
      selection: TextUTF16Range(location: 0, length: 5),
      identity: identity
    )
    let sources = ManualFakeSources(language: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)

    let result = await coordinator.convertSelectionOrLastWord()
    XCTAssertEqual(result, .cancelled(.unsupportedText))
    XCTAssertEqual(rewriter.replaceCount, 0)
  }

  func testUserExcludedApplicationBlocksManualMutationBeforeTextRead() async {
    let rewriter = ManualFakeRewriter(
      document: "gksrmffh",
      selection: TextUTF16Range(location: 8, length: 0),
      identity: identity,
      bundleIdentifier: "com.example.PrivateEditor"
    )
    let sources = ManualFakeSources(language: .english)
    let coordinator = ManualCorrectionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      isApplicationExcluded: { $0 == "com.example.PrivateEditor" },
      verificationAttempts: 1,
      delay: {}
    )

    let result = await coordinator.convertSelectionOrLastWord()

    XCTAssertEqual(result, .cancelled(.selectionUnavailable))
    XCTAssertEqual(rewriter.replaceCount, 0)
  }

  private func makeCoordinator(
    rewriter: ManualFakeRewriter,
    sources: ManualFakeSources
  ) -> ManualCorrectionCoordinator {
    ManualCorrectionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      verificationAttempts: 1,
      delay: {}
    )
  }
}

@MainActor
private final class ManualFakeRewriter: FocusedTextRewriting {
  var document: String
  var selection: TextUTF16Range
  var identity: FocusedElementIdentity
  var bundleIdentifier: String?
  private(set) var replaceCount = 0

  init(
    document: String,
    selection: TextUTF16Range,
    identity: FocusedElementIdentity,
    bundleIdentifier: String? = nil
  ) {
    self.document = document
    self.selection = selection
    self.identity = identity
    self.bundleIdentifier = bundleIdentifier
  }

  func currentSnapshot() -> FocusedTextSnapshot? {
    FocusedTextSnapshot(
      identity: identity,
      selection: selection,
      bundleIdentifier: bundleIdentifier
    )
  }

  func text(in range: TextUTF16Range, matching snapshot: FocusedTextSnapshot) -> String? {
    guard snapshot.identity == identity else { return nil }
    let value = document as NSString
    guard range.location >= 0, range.upperBound <= value.length else { return nil }
    return value.substring(with: NSRange(location: range.location, length: range.length))
  }

  func replace(
    range: TextUTF16Range,
    with text: String,
    matching snapshot: FocusedTextSnapshot
  ) -> Bool {
    replaceCount += 1
    guard snapshot.identity == identity else { return false }
    let value = NSMutableString(string: document)
    guard range.location >= 0, range.upperBound <= value.length else { return false }
    value.replaceCharacters(in: NSRange(location: range.location, length: range.length), with: text)
    document = value as String
    selection = TextUTF16Range(location: range.location + text.utf16.count, length: 0)
    return true
  }
}

@MainActor
private final class ManualFakeSources: InputSourceControlling {
  var current: InputSourceSnapshot?

  init(language: TokenLanguage) {
    current = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: language),
      language: language
    )
  }

  func currentSource() -> InputSourceSnapshot? { current }

  func select(language: TokenLanguage) -> InputSourceSnapshot? {
    let selected = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: language),
      language: language
    )
    current = selected
    return selected
  }
}
