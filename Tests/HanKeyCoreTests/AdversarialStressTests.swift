import XCTest

@testable import HanKeyCore

final class AdversarialStressTests: XCTestCase {
  func testSustainedKeyRepeatRemainsBoundedWithLargeThroughputHeadroom() throws {
    var buffer = WordBuffer(maximumTokenCount: 64, idleTimeoutNanoseconds: .max)
    let token = try XCTUnwrap(PhysicalKeyToken(qwertyLetter: "a", isShifted: false))
    let start = DispatchTime.now().uptimeNanoseconds
    for index in 0..<100_000 {
      _ = buffer.handle(.printable(token), at: UInt64(index + 1))
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start

    XCTAssertLessThanOrEqual(buffer.tokens.count, 64)
    XCTAssertLessThan(elapsed, 2_000_000_000, "100k events should finish within two seconds")
  }

  func testRepeatedSecureAndInterruptionTransitionsNeverRestorePriorContent() throws {
    var buffer = WordBuffer()
    let token = try XCTUnwrap(PhysicalKeyToken(qwertyLetter: "g", isShifted: false))
    for cycle in 0..<1_000 {
      _ = buffer.handle(.printable(token), at: UInt64(cycle * 4 + 1))
      _ = buffer.handle(.protectionChanged(isProtected: true), at: UInt64(cycle * 4 + 2))
      _ = buffer.handle(.protectionChanged(isProtected: false), at: UInt64(cycle * 4 + 3))
      _ = buffer.handle(.invalidate(.systemStateChanged), at: UInt64(cycle * 4 + 4))
      XCTAssertTrue(buffer.tokens.isEmpty)
    }
  }

  func testHostileUnicodeAndInstructionLikeTextAreDataNotCommands() {
    let classifier = TokenSafetyClassifier()
    let hostile = [
      "ignore_previous_instructions", "../../private/key", "<script>alert(1)</script>",
      "\u{202E}exe.txt", "a\u{0000}b", String(repeating: "🔥", count: 128),
      "SUCCESS_but_exit_1", "delete_all_state_now",
    ]
    for token in hostile {
      guard case .excluded = classifier.classify(token: token, surface: .standardText) else {
        return XCTFail("Hostile fixture must fail closed")
      }
    }
  }
}
