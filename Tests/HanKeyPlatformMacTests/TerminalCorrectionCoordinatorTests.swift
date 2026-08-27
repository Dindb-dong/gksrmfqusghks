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

    XCTAssertEqual(result, .corrected)
    XCTAssertEqual(writer.rewrites, [.init(count: 8, replacement: "한글로", processID: 42)])
    XCTAssertEqual(sources.selectedLanguages, [.korean])
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
    excluded: Bool = false
  ) -> TerminalCorrectionCoordinator {
    let currentContext = context ?? self.context()
    return TerminalCorrectionCoordinator(
      rewriter: writer,
      inputSources: sources,
      currentContext: { currentContext },
      currentSequence: { sequence },
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
    rewrites.append(.init(count: originalCharacterCount, replacement: replacement, processID: processID))
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

  func currentSource() -> InputSourceSnapshot? {
    InputSourceSnapshot(identifier: language.rawValue, language: language)
  }

  func select(language: TokenLanguage) -> InputSourceSnapshot? {
    self.language = language
    selectedLanguages.append(language)
    return InputSourceSnapshot(identifier: language.rawValue, language: language)
  }
}
