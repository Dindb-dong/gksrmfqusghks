import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class TerminalCorrectionCoordinatorTests: XCTestCase {
  private let identity = FocusedElementIdentity(processID: 42, elementHash: 7)

  func testSpaceCorrectionRevalidatesAndRewritesThenSwitchesSource() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .english)
    let coordinator = makeCoordinator(writer: writer, sources: sources)

    let result = await coordinator.perform(
      proposal: proposal,
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    XCTAssertEqual(
      result,
      .corrected(
        TerminalCorrectionRecord(
          focusIdentity: identity,
          correctionStart: 0,
          correctedCaretLocation: 4
        )
      )
    )
    XCTAssertEqual(writer.rewrites, [.init(count: 8, replacement: "한글로", processID: 42)])
    XCTAssertEqual(sources.selectedLanguages, [.korean])
  }

  func testLeadingSlashOffsetsTerminalRewriteWithoutDeletingPrefix() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .korean)
    let coordinator = makeCoordinator(
      writer: writer,
      sources: sources,
      initialCaret: 8,
      correctedCaret: 9
    )
    let original = "채ㅡㅔㅁㅊㅅ"

    let result = await coordinator.perform(
      proposal: CorrectionProposal(
        original: original,
        replacement: "compact",
        targetLanguage: .english,
        confidence: 1,
        usedExplicitRule: false
      ),
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    XCTAssertEqual(
      result,
      .corrected(
        TerminalCorrectionRecord(
          focusIdentity: identity,
          correctionStart: 1,
          correctedCaretLocation: 9
        )
      )
    )
    XCTAssertEqual(writer.rewrites, [.init(count: 6, replacement: "compact", processID: 42)])
    XCTAssertEqual(sources.selectedLanguages, [.english])
  }

  func testRetriesUntilCmuxPublishesCaretAfterSpaceCommit() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .korean)
    var preRewriteReads = 0
    let coordinator = TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { self.context() },
      currentSequence: { 9 },
      currentCaret: {
        if writer.rewrites.isEmpty {
          preRewriteReads += 1
          return FocusedTextSnapshot(
            identity: self.identity,
            selection: TextUTF16Range(location: preRewriteReads == 1 ? 7 : 8, length: 0),
            bundleIdentifier: "com.cmuxterm.app"
          )
        }
        return FocusedTextSnapshot(
          identity: self.identity,
          selection: TextUTF16Range(location: 9, length: 0),
          bundleIdentifier: "com.cmuxterm.app"
        )
      },
      isSecureInputEnabled: { false },
      delay: {}
    )
    let original = "채ㅡㅔㅁㅊㅅ"

    let result = await coordinator.perform(
      proposal: CorrectionProposal(
        original: original,
        replacement: "compact",
        targetLanguage: .english,
        confidence: 1,
        usedExplicitRule: false
      ),
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    guard case .corrected(let record) = result else {
      return XCTFail("Expected delayed cmux caret to be retried, got \(result)")
    }
    XCTAssertEqual(record.correctionStart, 1)
    XCTAssertEqual(writer.rewrites, [.init(count: 6, replacement: "compact", processID: 42)])
  }

  func testRetriesOnlyWhileTerminalCaretIsUnavailable() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .english)
    var unavailableReads = 2
    var delayCount = 0
    let coordinator = TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { self.context() },
      currentSequence: { 9 },
      currentCaret: {
        if unavailableReads > 0 {
          unavailableReads -= 1
          return nil
        }
        return FocusedTextSnapshot(
          identity: self.identity,
          selection: TextUTF16Range(
            location: writer.rewrites.isEmpty ? 9 : 4,
            length: 0
          ),
          bundleIdentifier: "com.cmuxterm.app"
        )
      },
      isSecureInputEnabled: { false },
      delay: { delayCount += 1 }
    )

    let result = await coordinator.perform(
      proposal: proposal,
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    guard case .corrected = result else {
      return XCTFail("Expected a temporarily unavailable caret to recover, got \(result)")
    }
    XCTAssertEqual(delayCount, 4)
    XCTAssertEqual(writer.rewrites.count, 1)
  }

  func testStableTerminalCorrectsWithoutWaitingThroughEveryRetryWindow() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .english)
    var sequence: UInt64 = 9
    var delayCount = 0
    let coordinator = TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { self.context() },
      currentSequence: { sequence },
      currentCaret: {
        FocusedTextSnapshot(
          identity: self.identity,
          selection: TextUTF16Range(
            location: writer.rewrites.isEmpty ? 9 : 4,
            length: 0
          ),
          bundleIdentifier: "com.cmuxterm.app"
        )
      },
      isSecureInputEnabled: { false },
      delay: {
        delayCount += 1
        if delayCount == 2 {
          sequence = 10
        }
      }
    )

    let result = await coordinator.perform(
      proposal: proposal,
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    guard case .corrected = result else {
      return XCTFail("Expected the stable first post-Space snapshot to correct, got \(result)")
    }
    XCTAssertEqual(delayCount, 2, "Only the pre-rewrite settle and post-rewrite verification may wait")
    XCTAssertEqual(writer.rewrites.count, 1)
  }

  func testInputSourceChangeDuringCmuxSettlingCancelsBeforeMutation() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .english)
    var delayCount = 0
    let coordinator = TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { self.context() },
      currentSequence: { 9 },
      currentCaret: {
        FocusedTextSnapshot(
          identity: self.identity,
          selection: TextUTF16Range(location: 9, length: 0),
          bundleIdentifier: "com.cmuxterm.app"
        )
      },
      isSecureInputEnabled: { false },
      delay: {
        delayCount += 1
        if delayCount == 1 {
          sources.changeLanguage(to: .korean)
        }
      }
    )

    let result = await coordinator.perform(
      proposal: proposal,
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    XCTAssertEqual(result, .cancelled(.sourceChanged))
    XCTAssertTrue(writer.rewrites.isEmpty)
    XCTAssertTrue(sources.selectedLanguages.isEmpty)
  }

  func testEveryNonSpaceBoundaryFailsClosedBeforeMutation() async {
    for boundary in [WordBoundary.returnKey, .tab, .punctuation] {
      let writer = FakeTerminalWriter()
      let sources = FakeTerminalInputSources(language: .english)
      let coordinator = makeCoordinator(writer: writer, sources: sources)

      let result = await coordinator.perform(
        proposal: proposal,
        boundary: boundary,
        expectedFocus: identity,
        expectedEventSequence: 9
      )

      XCTAssertEqual(result, .cancelled(.unsafeBoundary))
      XCTAssertTrue(writer.rewrites.isEmpty)
      XCTAssertTrue(sources.selectedLanguages.isEmpty)
    }
  }

  func testNewPhysicalEventCancelsBeforeMutation() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .english)
    let coordinator = makeCoordinator(writer: writer, sources: sources, sequence: 10)

    let result = await coordinator.perform(
      proposal: proposal,
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    XCTAssertEqual(result, .cancelled(.eventSequenceChanged))
    XCTAssertTrue(writer.rewrites.isEmpty)
  }

  func testCaretMovementWithoutAKeyEventCancelsBeforeMutation() async {
    let writer = FakeTerminalWriter()
    let sources = FakeTerminalInputSources(language: .english)
    var readCount = 0
    let coordinator = TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { self.context() },
      currentSequence: { 9 },
      currentCaret: {
        defer { readCount += 1 }
        return FocusedTextSnapshot(
          identity: self.identity,
          selection: TextUTF16Range(location: readCount == 0 ? 9 : 11, length: 0),
          bundleIdentifier: "com.cmuxterm.app"
        )
      },
      delay: {}
    )

    let result = await coordinator.perform(
      proposal: proposal,
      boundary: .space,
      expectedFocus: identity,
      expectedEventSequence: 9
    )

    XCTAssertEqual(result, .cancelled(.selectionChanged))
    XCTAssertTrue(writer.rewrites.isEmpty)
  }

  func testSecureInputFocusChangeSurfaceChangeAndExclusionFailClosed() async {
    let cases: [(FocusedElementContext, Bool, Bool, TerminalCorrectionFailure)] = [
      (context(), true, false, .secureInput),
      (
        context(identity: FocusedElementIdentity(processID: 43, elementHash: 7)),
        false,
        false,
        .focusChanged
      ),
      (context(surface: .standardText), false, false, .surfaceChanged),
      (context(), false, true, .applicationExcluded),
    ]

    for (context, secureInput, excluded, expectedFailure) in cases {
      let writer = FakeTerminalWriter()
      let sources = FakeTerminalInputSources(language: .english)
      let coordinator = makeCoordinator(
        writer: writer,
        sources: sources,
        context: context,
        secureInput: secureInput,
        excluded: excluded
      )
      let result = await coordinator.perform(
        proposal: proposal,
        boundary: .space,
        expectedFocus: identity,
        expectedEventSequence: 9
      )
      XCTAssertEqual(result, .cancelled(expectedFailure))
      XCTAssertTrue(writer.rewrites.isEmpty)
    }
  }

  private var proposal: CorrectionProposal {
    CorrectionProposal(
      original: "gksrmffh",
      replacement: "한글로",
      targetLanguage: .korean,
      confidence: 1,
      usedExplicitRule: false
    )
  }

  private func context(
    identity: FocusedElementIdentity? = nil,
    surface: InputSurface = .terminal
  ) -> FocusedElementContext {
    FocusedElementContext(
      state: .editable,
      identity: identity ?? self.identity,
      surface: surface,
      bundleIdentifier: "com.cmuxterm.app"
    )
  }

  private func makeCoordinator(
    writer: FakeTerminalWriter,
    sources: FakeTerminalInputSources,
    sequence: UInt64 = 9,
    context: FocusedElementContext? = nil,
    secureInput: Bool = false,
    excluded: Bool = false,
    initialCaret: Int = 9,
    correctedCaret: Int = 4
  ) -> TerminalCorrectionCoordinator {
    let currentContext = context ?? self.context()
    return TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { currentContext },
      currentSequence: { sequence },
      currentCaret: {
        let location = writer.rewrites.isEmpty ? initialCaret : correctedCaret
        return FocusedTextSnapshot(
          identity: currentContext.identity ?? self.identity,
          selection: TextUTF16Range(
            location: location,
            length: 0
          ),
          bundleIdentifier: currentContext.bundleIdentifier
        )
      },
      isApplicationExcluded: { _ in excluded },
      isSecureInputEnabled: { secureInput },
      delay: {}
    )
  }
}

@MainActor
private final class FakeTerminalWriter: TerminalEventRewriting {
  struct Rewrite: Equatable {
    let count: Int
    let replacement: String
    let processID: Int32
  }

  private(set) var rewrites: [Rewrite] = []

  func rewrite(
    originalCharacterCount: Int,
    replacement: String,
    processID: Int32
  ) -> Bool {
    rewrites.append(
      .init(count: originalCharacterCount, replacement: replacement, processID: processID))
    return true
  }
}

@MainActor
private final class FakeTerminalInputSources: InputSourceControlling {
  private var language: TokenLanguage
  private(set) var selectedLanguages: [TokenLanguage] = []

  init(language: TokenLanguage) {
    self.language = language
  }

  func changeLanguage(to language: TokenLanguage) {
    self.language = language
  }

  func currentSource() -> InputSourceSnapshot? {
    InputSourceSnapshot(identifier: language.rawValue, language: language)
  }

  func select(language: TokenLanguage) -> InputSourceSnapshot? {
    self.language = language
    selectedLanguages.append(language)
    return InputSourceSnapshot(identifier: language.rawValue, language: language)
  }
}
