import XCTest

@testable import HanKeyCore

final class CorrectionDeletionTrackerTests: XCTestCase {
  func testPlainBackspacesMustReachExactCorrectionStart() throws {
    let word = try bufferedWord("skdltm")
    var tracker = CorrectionDeletionTracker()
    tracker.beginTracking(word: word, correctionStart: 10, correctedCaretLocation: 14)

    XCTAssertEqual(tracker.observeCaret(location: 13), .none)
    XCTAssertEqual(tracker.observeCaret(location: 12), .none)
    XCTAssertEqual(tracker.observeCaret(location: 11), .none)
    XCTAssertEqual(tracker.observeCaret(location: 10), .correctionFullyDeleted(word))
    XCTAssertFalse(tracker.isTracking)
  }

  func testOptionOrCommandBackspaceCanReachStartInOneCaretJump() throws {
    let word = try bufferedWord("skdltm")
    var tracker = CorrectionDeletionTracker()
    tracker.beginTracking(word: word, correctionStart: 10, correctedCaretLocation: 14)

    XCTAssertEqual(tracker.observeCaret(location: 10), .correctionFullyDeleted(word))
  }

  func testOverDeletionCaretGrowthAndUnchangedCaretCancel() throws {
    for invalidLocation in [9, 14, 15] {
      var tracker = CorrectionDeletionTracker()
      tracker.beginTracking(
        word: try bufferedWord("skdltm"),
        correctionStart: 10,
        correctedCaretLocation: 14
      )
      XCTAssertEqual(tracker.observeCaret(location: invalidLocation), .cancelled)
      XCTAssertFalse(tracker.isTracking)
    }
  }

  func testNonDeletionInputCancelsTracking() throws {
    var tracker = CorrectionDeletionTracker()
    tracker.beginTracking(
      word: try bufferedWord("skdltm"),
      correctionStart: 10,
      correctedCaretLocation: 14
    )

    XCTAssertEqual(tracker.cancel(), .cancelled)
    XCTAssertEqual(tracker.observeCaret(location: 10), .none)
  }

  func testNewCorrectionReplacesPriorTrackingWithoutRetainingText() throws {
    let first = try bufferedWord("skdltm")
    let second = try bufferedWord("gksrmf")
    var tracker = CorrectionDeletionTracker()
    tracker.beginTracking(word: first, correctionStart: 4, correctedCaretLocation: 7)
    tracker.beginTracking(word: second, correctionStart: 20, correctedCaretLocation: 24)

    XCTAssertEqual(tracker.observeCaret(location: 20), .correctionFullyDeleted(second))
  }

  private func bufferedWord(_ ascii: String) throws -> BufferedWord {
    BufferedWord(
      tokens: try ascii.map { character in
        try XCTUnwrap(PhysicalKeyToken(ascii: character))
      }
    )
  }
}
