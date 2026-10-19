import XCTest

@testable import HanKeyCore

final class InputHandoffBufferTests: XCTestCase {
  func testReleasedPrefixPrecedesNewEventAndIsClaimedOnce() throws {
    var queue = InputHandoffBuffer<Int>()
    let token = try XCTUnwrap(queue.begin(now: 0))
    for value in 0..<16 {
      guard case .buffered = queue.receive(now: 1, copy: { value }) else {
        return XCTFail("Expected buffered event")
      }
    }
    XCTAssertTrue(queue.requestRelease(token))
    XCTAssertNil(queue.begin(now: 2))
    guard case .pass(let prefix) = queue.receive(now: 3, copy: { 16 }) else {
      return XCTFail("Release must precede the current event")
    }
    XCTAssertEqual(prefix + [16], Array(0...16))
    XCTAssertTrue(queue.drain().isEmpty)
    XCTAssertFalse(queue.requestRelease(token))
    XCTAssertNotNil(queue.begin(now: 4))
  }

  func testDeadlineOverflowAndCopyFailureReleaseOriginalsWithoutRetry() throws {
    for mode in 0..<3 {
      var queue = InputHandoffBuffer<Int>(maximumCount: mode == 1 ? 1 : 8)
      let token = try XCTUnwrap(queue.begin(now: 0))
      _ = queue.receive(now: 1, copy: { 7 })
      let now: UInt64 = mode == 0 ? InputHandoffBuffer<Int>.durationNanoseconds : 2
      guard case .pass(let prefix) = queue.receive(now: now, copy: { mode == 2 ? nil : 8 }) else {
        return XCTFail("Expected fail-open physical input release")
      }
      XCTAssertEqual(prefix, [7])
      XCTAssertFalse(queue.isValid(token, now: now))
      XCTAssertTrue(queue.drain().isEmpty)
    }
  }

  func testStaleDeadlineAndWakeDoNotReleaseNewHandoff() throws {
    var queue = InputHandoffBuffer<Int>()
    let first = try XCTUnwrap(queue.begin(now: 0))
    XCTAssertFalse(queue.requestRelease(first))
    let second = try XCTUnwrap(queue.begin(now: 190_000_000))
    _ = queue.receive(now: 191_000_000, copy: { 9 })
    XCTAssertFalse(queue.expire(first, now: 200_000_000))
    XCTAssertFalse(queue.requestRelease(first))
    XCTAssertFalse(queue.needsDrain(now: 200_000_000))
    XCTAssertTrue(queue.isValid(second, now: 200_000_000))
    XCTAssertTrue(queue.expire(second, now: 390_000_000))
    XCTAssertFalse(queue.isValid(second, now: 390_000_000))
    XCTAssertEqual(queue.drain(), [9])
    XCTAssertTrue(queue.drain().isEmpty)
  }

  func testIdlePathDoesNotCopyInputAndReservesMutationTime() throws {
    var queue = InputHandoffBuffer<Int>()
    guard
      case .pass(let prefix) = queue.receive(
        now: 0,
        copy: {
          XCTFail("Idle copy")
          return 1
        })
    else { return XCTFail("Idle input must pass") }
    XCTAssertTrue(prefix.isEmpty)
    let token = try XCTUnwrap(queue.begin(now: 0))
    XCTAssertTrue(queue.isValid(token, now: 184_999_999))
    XCTAssertFalse(queue.isValid(token, now: 185_000_000))
  }
}
