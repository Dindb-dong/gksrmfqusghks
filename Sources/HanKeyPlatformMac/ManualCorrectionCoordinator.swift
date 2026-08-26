import Foundation
import HanKeyCore

public enum ManualCorrectionFailure: Equatable, Sendable {
  case busy
  case sourceUnavailable
  case selectionUnavailable
  case unsupportedText
  case replacementRejected
  case replacementUnverified
  case sourceSwitchFailed(CorrectionTransactionRecord)
}

public enum ManualCorrectionResult: Equatable, Sendable {
  case corrected(CorrectionTransactionRecord)
  case cancelled(ManualCorrectionFailure)
}

public enum CorrectionUndoResult: Equatable, Sendable {
  case undone
  case unavailable
  case contextChanged
  case replacementRejected
  case replacementUnverified
  case sourceSwitchFailed
}

@MainActor
public final class ManualCorrectionCoordinator {
  public typealias Delay = @MainActor @Sendable () async -> Void
  public typealias ExclusionProvider = @MainActor (String?) -> Bool

  private let rewriter: any FocusedTextRewriting
  private let inputSources: any InputSourceControlling
  private let isApplicationExcluded: ExclusionProvider
  private let delay: Delay
  private let verificationAttempts: Int
  private var isBusy = false

  public init(
    rewriter: any FocusedTextRewriting = FocusedTextRewriter(),
    inputSources: any InputSourceControlling = InputSourceController(),
    isApplicationExcluded: @escaping ExclusionProvider = { _ in false },
    verificationAttempts: Int = 4,
    delay: @escaping Delay = {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) {
          continuation.resume()
        }
      }
    }
  ) {
    precondition(verificationAttempts > 0)
    self.rewriter = rewriter
    self.inputSources = inputSources
    self.isApplicationExcluded = isApplicationExcluded
    self.verificationAttempts = verificationAttempts
    self.delay = delay
  }

  public func convertSelectionOrLastWord() async -> ManualCorrectionResult {
    guard !isBusy else {
      return .cancelled(.busy)
    }
    isBusy = true
    defer { isBusy = false }

    guard let sourceBefore = inputSources.currentSource() else {
      return .cancelled(.sourceUnavailable)
    }
    guard
      let snapshot = rewriter.currentSnapshot(),
      !isApplicationExcluded(snapshot.bundleIdentifier),
      let target = resolveTarget(in: snapshot)
    else {
      return .cancelled(.selectionUnavailable)
    }
    guard let conversion = converted(target.text) else {
      return .cancelled(.unsupportedText)
    }
    guard
      rewriter.replace(
        range: target.range,
        with: conversion.text,
        matching: snapshot
      )
    else {
      return .cancelled(.replacementRejected)
    }

    let expectedCaret = target.range.location + conversion.text.utf16.count
    guard await verifyCaret(identity: snapshot.identity, location: expectedCaret) else {
      return .cancelled(.replacementUnverified)
    }

    let provisionalRecord = CorrectionTransactionRecord(
      focusIdentity: snapshot.identity,
      originalWithBoundary: target.text,
      replacementWithBoundary: conversion.text,
      replacedRange: target.range,
      sourceBefore: sourceBefore,
      sourceAfter: nil
    )
    guard let sourceAfter = inputSources.select(language: conversion.targetLanguage) else {
      return .cancelled(.sourceSwitchFailed(provisionalRecord))
    }
    return .corrected(
      CorrectionTransactionRecord(
        focusIdentity: snapshot.identity,
        originalWithBoundary: target.text,
        replacementWithBoundary: conversion.text,
        replacedRange: target.range,
        sourceBefore: sourceBefore,
        sourceAfter: sourceAfter
      )
    )
  }

  public func undo(_ record: CorrectionTransactionRecord?) async -> CorrectionUndoResult {
    guard !isBusy, let record else {
      return .unavailable
    }
    isBusy = true
    defer { isBusy = false }

    guard
      let snapshot = rewriter.currentSnapshot(),
      snapshot.identity == record.focusIdentity,
      snapshot.selection.length == 0,
      snapshot.selection.location
        == record.replacedRange.location + record.replacementWithBoundary.utf16.count
    else {
      return .contextChanged
    }
    let currentRange = TextUTF16Range(
      location: record.replacedRange.location,
      length: record.replacementWithBoundary.utf16.count
    )
    guard rewriter.text(in: currentRange, matching: snapshot) == record.replacementWithBoundary
    else {
      return .contextChanged
    }
    guard
      rewriter.replace(
        range: currentRange,
        with: record.originalWithBoundary,
        matching: snapshot
      )
    else {
      return .replacementRejected
    }
    let expectedCaret = currentRange.location + record.originalWithBoundary.utf16.count
    guard await verifyCaret(identity: record.focusIdentity, location: expectedCaret) else {
      return .replacementUnverified
    }
    guard inputSources.select(language: record.sourceBefore.language) != nil else {
      return .sourceSwitchFailed
    }
    return .undone
  }

  private func resolveTarget(
    in snapshot: FocusedTextSnapshot
  ) -> (range: TextUTF16Range, text: String)? {
    if snapshot.selection.length > 0 {
      guard snapshot.selection.length <= 256 else {
        return nil
      }
      guard let selected = rewriter.text(in: snapshot.selection, matching: snapshot) else {
        return nil
      }
      return (snapshot.selection, selected)
    }

    let contextLength = min(64, snapshot.selection.location)
    guard contextLength > 0 else {
      return nil
    }
    let contextRange = TextUTF16Range(
      location: snapshot.selection.location - contextLength,
      length: contextLength
    )
    guard let context = rewriter.text(in: contextRange, matching: snapshot) else {
      return nil
    }
    let characters = context.reversed().prefix { character in
      character.isLetter || character.unicodeScalars.allSatisfy { isHangul($0.value) }
    }
    let word = String(characters.reversed())
    guard !word.isEmpty else {
      return nil
    }
    return (
      TextUTF16Range(
        location: snapshot.selection.location - word.utf16.count,
        length: word.utf16.count
      ),
      word
    )
  }

  private func converted(_ text: String) -> (text: String, targetLanguage: TokenLanguage)? {
    let scalars = text.unicodeScalars
    let hasHangul = scalars.contains { isHangul($0.value) }
    let hasLatin = text.contains { $0.isASCII && $0.isLetter }
    guard hasHangul != hasLatin else {
      return nil
    }
    if hasHangul {
      let replacement = DubeolsikConverter.decomposeToQWERTY(text)
      return replacement != text ? (replacement, .english) : nil
    }
    guard text.allSatisfy({ $0.isASCII && $0.isLetter }) else {
      return nil
    }
    let replacement = DubeolsikConverter.compose(text)
    return replacement != text ? (replacement, .korean) : nil
  }

  private func verifyCaret(identity: FocusedElementIdentity, location: Int) async -> Bool {
    for _ in 0..<verificationAttempts {
      await delay()
      guard let snapshot = rewriter.currentSnapshot(), snapshot.identity == identity else {
        return false
      }
      if snapshot.selection == TextUTF16Range(location: location, length: 0) {
        return true
      }
    }
    return false
  }

  private func isHangul(_ scalar: UInt32) -> Bool {
    (0xAC00...0xD7A3).contains(scalar)
      || (0x1100...0x11FF).contains(scalar)
      || (0x3130...0x318F).contains(scalar)
      || (0xA960...0xA97F).contains(scalar)
      || (0xD7B0...0xD7FF).contains(scalar)
  }
}
