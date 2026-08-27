import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import HanKeyCore

public enum TerminalCorrectionFailure: Equatable, Sendable {
  case busy
  case unsafeBoundary
  case sourceUnavailable
  case sourceChanged
  case eventSequenceChanged
  case focusChanged
  case selectionUnavailable
  case selectionChanged
  case surfaceChanged
  case secureInput
  case applicationExcluded
  case rewriteRejected
  case rewriteUnverified
  case sourceSwitchFailed(TerminalCorrectionRecord)
}

public enum TerminalCorrectionResult: Equatable, Sendable {
  case corrected(TerminalCorrectionRecord)
  case cancelled(TerminalCorrectionFailure)
}

public struct TerminalCorrectionRecord: Equatable, Sendable {
  public let focusIdentity: FocusedElementIdentity
  public let correctionStart: Int
  public let correctedCaretLocation: Int

  public init(
    focusIdentity: FocusedElementIdentity,
    correctionStart: Int,
    correctedCaretLocation: Int
  ) {
    self.focusIdentity = focusIdentity
    self.correctionStart = correctionStart
    self.correctedCaretLocation = correctedCaretLocation
  }
}

@MainActor
public protocol TerminalEventRewriting: AnyObject {
  func rewrite(
    originalCharacterCount: Int,
    replacement: String,
    processID: Int32
  ) -> Bool
}

@MainActor
public final class TerminalCorrectionCoordinator {
  public typealias Delay = @MainActor @Sendable () async -> Void
  public typealias ContextProvider = @MainActor () -> FocusedElementContext
  public typealias SequenceProvider = @MainActor () -> UInt64
  public typealias CaretProvider = @MainActor () -> FocusedTextSnapshot?
  public typealias ExclusionProvider = @MainActor (String?) -> Bool
  public typealias SecureInputProvider = @MainActor () -> Bool

  private let rewriter: any TerminalEventRewriting
  private let inputSources: any InputSourceControlling
  private let currentContext: ContextProvider
  private let currentSequence: SequenceProvider
  private let currentCaret: CaretProvider
  private let isApplicationExcluded: ExclusionProvider
  private let isSecureInputEnabled: SecureInputProvider
  private let delay: Delay
  private let settlingAttempts: Int
  private var isBusy = false

  public init(
    rewriter: any TerminalEventRewriting = CGTerminalEventRewriter(),
    inputSources: any InputSourceControlling = InputSourceController(),
    currentContext: @escaping ContextProvider = {
      FocusedElementSecurityInspector.currentContext()
    },
    currentSequence: @escaping SequenceProvider,
    currentCaret: @escaping CaretProvider = { TerminalCaretInspector.currentSnapshot() },
    isApplicationExcluded: @escaping ExclusionProvider = { _ in false },
    isSecureInputEnabled: @escaping SecureInputProvider = {
      PlatformCapabilities.currentPermissionSnapshot().isSecureInputEnabled
    },
    settlingAttempts: Int = 4,
    delay: @escaping Delay = {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) {
          continuation.resume()
        }
      }
    }
  ) {
    precondition(settlingAttempts > 0)
    self.rewriter = rewriter
    self.inputSources = inputSources
    self.currentContext = currentContext
    self.currentSequence = currentSequence
    self.currentCaret = currentCaret
    self.isApplicationExcluded = isApplicationExcluded
    self.isSecureInputEnabled = isSecureInputEnabled
    self.settlingAttempts = settlingAttempts
    self.delay = delay
  }

  public func perform(
    proposal: CorrectionProposal,
    boundary: WordBoundary,
    expectedFocus: FocusedElementIdentity,
    expectedEventSequence: UInt64
  ) async -> TerminalCorrectionResult {
    guard !isBusy else { return .cancelled(.busy) }
    isBusy = true
    defer { isBusy = false }

    guard boundary == .space else { return .cancelled(.unsafeBoundary) }
    guard let sourceBefore = inputSources.currentSource() else {
      return .cancelled(.sourceUnavailable)
    }
    guard sourceBefore.language == proposal.targetLanguage.opposite else {
      return .cancelled(.sourceChanged)
    }
    var expectedCaret: FocusedTextSnapshot?
    var observedBoundaryAdvance = false
    for _ in 0..<settlingAttempts {
      await delay()
      guard currentSequence() == expectedEventSequence else {
        return .cancelled(.eventSequenceChanged)
      }
      guard !isSecureInputEnabled() else { return .cancelled(.secureInput) }
      let settlingContext = currentContext()
      guard settlingContext.identity == expectedFocus else {
        return .cancelled(.focusChanged)
      }
      guard settlingContext.state == .editable, settlingContext.surface == .terminal else {
        return .cancelled(.surfaceChanged)
      }
      guard !isApplicationExcluded(settlingContext.bundleIdentifier) else {
        return .cancelled(.applicationExcluded)
      }
      guard let candidateCaret = currentCaret() else {
        continue
      }
      guard candidateCaret.identity == expectedFocus else {
        return .cancelled(.focusChanged)
      }
      guard candidateCaret.selection.length == 0 else {
        return .cancelled(.selectionChanged)
      }
      if let previousCaret = expectedCaret, candidateCaret != previousCaret {
        let isSingleSpaceAdvance =
          !observedBoundaryAdvance
          && candidateCaret.identity == previousCaret.identity
          && candidateCaret.selection.location == previousCaret.selection.location + 1
        guard isSingleSpaceAdvance else {
          return .cancelled(.selectionChanged)
        }
        observedBoundaryAdvance = true
      }
      expectedCaret = candidateCaret
    }
    guard let expectedCaret else { return .cancelled(.selectionUnavailable) }
    let correctionStart = expectedCaret.selection.location - proposal.original.utf16.count - 1
    guard correctionStart >= 0 else { return .cancelled(.selectionUnavailable) }

    guard currentSequence() == expectedEventSequence else {
      return .cancelled(.eventSequenceChanged)
    }
    guard !isSecureInputEnabled() else { return .cancelled(.secureInput) }

    let context = currentContext()
    guard context.identity == expectedFocus else { return .cancelled(.focusChanged) }
    guard context.state == .editable, context.surface == .terminal else {
      return .cancelled(.surfaceChanged)
    }
    guard !isApplicationExcluded(context.bundleIdentifier) else {
      return .cancelled(.applicationExcluded)
    }
    guard inputSources.currentSource() == sourceBefore else {
      return .cancelled(.sourceChanged)
    }
    guard let verifiedCaret = currentCaret() else {
      return .cancelled(.selectionUnavailable)
    }
    guard verifiedCaret == expectedCaret else {
      return .cancelled(.selectionChanged)
    }
    guard currentSequence() == expectedEventSequence else {
      return .cancelled(.eventSequenceChanged)
    }
    guard
      rewriter.rewrite(
        originalCharacterCount: proposal.original.count,
        replacement: proposal.replacement,
        processID: expectedFocus.processID
      )
    else {
      return .cancelled(.rewriteRejected)
    }

    await delay()
    let correctedCaretLocation = correctionStart + (proposal.replacement + " ").utf16.count
    guard
      let correctedCaret = currentCaret(),
      correctedCaret.identity == expectedFocus,
      correctedCaret.selection == TextUTF16Range(location: correctedCaretLocation, length: 0)
    else {
      return .cancelled(.rewriteUnverified)
    }
    let record = TerminalCorrectionRecord(
      focusIdentity: expectedFocus,
      correctionStart: correctionStart,
      correctedCaretLocation: correctedCaretLocation
    )
    guard inputSources.select(language: proposal.targetLanguage) != nil else {
      return .cancelled(.sourceSwitchFailed(record))
    }
    return .corrected(record)
  }
}

public enum TerminalCaretInspector {
  @MainActor
  public static func currentSnapshot() -> FocusedTextSnapshot? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedUIElementAttribute as CFString,
        &focusedValue
      ) == .success,
      let focusedValue
    else { return nil }

    let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
    let context = FocusedElementSecurityInspector.context(for: element)
    guard context.state == .editable, context.surface == .terminal, let identity = context.identity
    else { return nil }

    var selectionValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &selectionValue
      ) == .success,
      let selectionValue,
      CFGetTypeID(selectionValue) == AXValueGetTypeID()
    else { return nil }

    let axValue = unsafeDowncast(selectionValue, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0
    else { return nil }

    return FocusedTextSnapshot(
      identity: identity,
      selection: TextUTF16Range(location: range.location, length: range.length),
      bundleIdentifier: context.bundleIdentifier
    )
  }
}

@MainActor
public final class CGTerminalEventRewriter: TerminalEventRewriting {
  public init() {}

  public func rewrite(
    originalCharacterCount: Int,
    replacement: String,
    processID: Int32
  ) -> Bool {
    guard originalCharacterCount > 0, processID > 0,
      let source = CGEventSource(stateID: .combinedSessionState)
    else { return false }

    var events: [(CGEvent, CGEvent)] = []
    for _ in 0..<(originalCharacterCount + 1) {
      guard
        let down = CGEvent(
          keyboardEventSource: source,
          virtualKey: CGKeyCode(kVK_Delete),
          keyDown: true
        ),
        let up = CGEvent(
          keyboardEventSource: source,
          virtualKey: CGKeyCode(kVK_Delete),
          keyDown: false
        )
      else { return false }
      events.append((down, up))
    }

    for segment in UnicodeEventText.segments(replacement + " ") {
      guard
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      else { return false }
      let utf16 = Array(segment.utf16)
      utf16.withUnsafeBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
        up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
      }
      events.append((down, up))
    }

    for (down, up) in events {
      HanKeySyntheticEvent.mark(down)
      HanKeySyntheticEvent.mark(up)
      down.postToPid(processID)
      up.postToPid(processID)
    }
    return true
  }
}
