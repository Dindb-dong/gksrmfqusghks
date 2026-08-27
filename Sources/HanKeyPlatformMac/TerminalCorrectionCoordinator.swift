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
  case surfaceChanged
  case secureInput
  case applicationExcluded
  case rewriteRejected
  case sourceSwitchFailed
}

public enum TerminalCorrectionResult: Equatable, Sendable {
  case corrected
  case cancelled(TerminalCorrectionFailure)
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
  public typealias ExclusionProvider = @MainActor (String?) -> Bool
  public typealias SecureInputProvider = @MainActor () -> Bool

  private let rewriter: any TerminalEventRewriting
  private let inputSources: any InputSourceControlling
  private let currentContext: ContextProvider
  private let currentSequence: SequenceProvider
  private let isApplicationExcluded: ExclusionProvider
  private let isSecureInputEnabled: SecureInputProvider
  private let delay: Delay
  private var isBusy = false

  public init(
    rewriter: any TerminalEventRewriting = CGTerminalEventRewriter(),
    inputSources: any InputSourceControlling = InputSourceController(),
    currentContext: @escaping ContextProvider = {
      FocusedElementSecurityInspector.currentContext()
    },
    currentSequence: @escaping SequenceProvider,
    isApplicationExcluded: @escaping ExclusionProvider = { _ in false },
    isSecureInputEnabled: @escaping SecureInputProvider = {
      PlatformCapabilities.currentPermissionSnapshot().isSecureInputEnabled
    },
    delay: @escaping Delay = {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) {
          continuation.resume()
        }
      }
    }
  ) {
    self.rewriter = rewriter
    self.inputSources = inputSources
    self.currentContext = currentContext
    self.currentSequence = currentSequence
    self.isApplicationExcluded = isApplicationExcluded
    self.isSecureInputEnabled = isSecureInputEnabled
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

    await delay()
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
    guard inputSources.select(language: proposal.targetLanguage) != nil else {
      return .cancelled(.sourceSwitchFailed)
    }
    return .corrected
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
