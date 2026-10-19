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
      makeInputHandoff: { TestInputHandoff() }
    )

    let result = await coordinator.convertSelectionOrLastWord()

    XCTAssertEqual(result, .cancelled(.selectionUnavailable))
    XCTAssertEqual(rewriter.replaceCount, 0)
  }

  func testExpiredHandoffDuringVerificationDoesNotSwitchAndAlwaysFinishes() async {
    let rewriter = ManualFakeRewriter(
      document: "gksrmffh",
      selection: TextUTF16Range(location: 8, length: 0), identity: identity)
    let sources = ManualFakeSources(language: .english)
    let handoff = TestInputHandoff()
    rewriter.onReplace = { handoff.isValid = false }
    let coordinator = ManualCorrectionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff })
    let result = await coordinator.convertSelectionOrLastWord()
    guard case .cancelled(.sourceSwitchFailed) = result else {
      return XCTFail("Expected handoff failure")
    }
    XCTAssertEqual(sources.current?.language, .english)
    XCTAssertEqual(handoff.finishCount, 1)
  }

  func testUndoExpiredHandoffDoesNotSwitchSourceAndAlwaysFinishes() async {
    let rewriter = ManualFakeRewriter(
      document: "gksrmffh",
      selection: TextUTF16Range(location: 8, length: 0), identity: identity)
    let sources = ManualFakeSources(language: .english)
    let first = makeCoordinator(rewriter: rewriter, sources: sources)
    guard case .corrected(let record) = await first.convertSelectionOrLastWord() else {
      return XCTFail("Expected initial conversion")
    }
    let handoff = TestInputHandoff()
    rewriter.onReplace = { handoff.isValid = false }
    let coordinator = ManualCorrectionCoordinator(
      rewriter: rewriter, inputSources: sources, makeInputHandoff: { handoff })
    let result = await coordinator.undo(record)
    XCTAssertEqual(result, .sourceSwitchFailed)
    XCTAssertEqual(sources.current?.language, .korean)
    XCTAssertEqual(handoff.finishCount, 1)
  }

  func testSourceSelectionSideEffectsAreUnverifiedEvenWhenSelectionFails() async {
    let rewriter = ManualFakeRewriter(
      document: "gksrmffh",
      selection: TextUTF16Range(location: 8, length: 0), identity: identity)
    let sources = ManualFakeSources(language: .english)
    sources.onSelect = { rewriter.document = "다른말" }
    sources.canSelect = false
    let result = await makeCoordinator(rewriter: rewriter, sources: sources)
      .convertSelectionOrLastWord()
    XCTAssertEqual(result, .cancelled(.replacementUnverified))
    XCTAssertEqual(rewriter.replaceCount, 1)
  }

  func testUndoSourceSelectionSideEffectsAreUnverified() async {
    let rewriter = ManualFakeRewriter(
      document: "gksrmffh",
      selection: TextUTF16Range(location: 8, length: 0), identity: identity)
    let sources = ManualFakeSources(language: .english)
    let coordinator = makeCoordinator(rewriter: rewriter, sources: sources)
    guard case .corrected(let record) = await coordinator.convertSelectionOrLastWord() else {
      return XCTFail("Expected initial conversion")
    }
    sources.onSelect = { rewriter.document = "different" }
    sources.canSelect = false
    let result = await coordinator.undo(record)
    XCTAssertEqual(result, .replacementUnverified)
    XCTAssertEqual(rewriter.replaceCount, 2)
  }

  private func makeCoordinator(
    rewriter: ManualFakeRewriter,
    sources: ManualFakeSources
  ) -> ManualCorrectionCoordinator {
    ManualCorrectionCoordinator(
      rewriter: rewriter,
      inputSources: sources,
      makeInputHandoff: { TestInputHandoff() }
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
  var onReplace: (() -> Void)?

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
    matching snapshot: FocusedTextSnapshot,
    isStillValid: @MainActor () -> Bool
  ) -> Bool {
    guard isStillValid(), snapshot.selection == selection else { return false }
    replaceCount += 1
    guard snapshot.identity == identity else { return false }
    let value = NSMutableString(string: document)
    guard range.location >= 0, range.upperBound <= value.length else { return false }
    value.replaceCharacters(in: NSRange(location: range.location, length: range.length), with: text)
    document = value as String
    selection = TextUTF16Range(location: range.location + text.utf16.count, length: 0)
    onReplace?()
    return true
  }
}

@MainActor
private final class ManualFakeSources: InputSourceControlling {
  var current: InputSourceSnapshot?
  var onSelect: (() -> Void)?
  var canSelect = true

  init(language: TokenLanguage) {
    current = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: language),
      language: language
    )
  }

  func currentSource() -> InputSourceSnapshot? { current }

  func select(language: TokenLanguage) -> InputSourceSnapshot? {
    onSelect?()
    guard canSelect else { return nil }
    let selected = InputSourceSnapshot(
      identifier: InputSourceController.identifier(for: language),
      language: language
    )
    current = selected
    return selected
  }
}
