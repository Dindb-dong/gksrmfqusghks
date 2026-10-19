import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

final class InputSourceControllerTests: XCTestCase {
  @MainActor
  func testPreparedSwitchIsOneShotAndReservesTheWholeChord() async throws {
    let center = NotificationCenter()
    var current = InputSourceSnapshot(
      identifier: InputSourceController.abcIdentifier, language: .english)
    var requests = 0
    let controller = InputSourceController(
      readSource: { current },
      selectSource: { language in
        requests += 1
        current = InputSourceSnapshot(
          identifier: InputSourceController.identifier(for: language), language: language)
        center.post(name: InputSourceController.sourceChanged, object: nil)
        return true
      }, notifications: center, acknowledgmentDelay: {})
    let expired = try XCTUnwrap(controller.prepareSelection(language: .korean))
    let expiredHandoff = TestInputHandoff()
    expiredHandoff.isValid = false
    let expiredResult = await expired.perform(isStillValid: { true }, handoff: expiredHandoff)
    XCTAssertNil(expiredResult)
    XCTAssertEqual(requests, 0)
    let prepared = try XCTUnwrap(controller.prepareSelection(language: .korean))
    let first = await prepared.perform(isStillValid: { true })
    let second = await prepared.perform(isStillValid: { true })
    XCTAssertEqual(first?.language, .korean)
    XCTAssertNil(second)
    XCTAssertEqual(requests, 1)
  }

  @MainActor
  func testNativeBranchDistinguishesBudgetDispatchAndAcknowledgmentFailures() async throws {
    for mode in 0..<5 {
      let handoff = TimedInputHandoff()
      handoff.now = mode == 0 ? 164_999_999 : (mode == 1 ? 165_000_000 : 100_000_000)
      if mode == 2 { handoff.queueDelayMilliseconds = 66 }
      let center = NotificationCenter()
      var source = InputSourceSnapshot(
        identifier: InputSourceController.abcIdentifier, language: .english)
      let controller = InputSourceController(
        readSource: { source },
        selectSource: { _ in
          XCTFail("Native branch must not use TIS")
          return false
        },
        prepareNativeSwitch: { NativeInputSourceSwitch(isCurrentContext: { mode != 4 }) },
        notifications: center, acknowledgmentDelay: {})
      if mode == 0 {
        handoff.onCommand = {
          source = InputSourceSnapshot(
            identifier: InputSourceController.korean2SetIdentifier, language: .korean)
          center.post(name: InputSourceController.sourceChanged, object: nil)
        }
      }
      let prepared = try XCTUnwrap(controller.prepareSelection(language: .korean))
      let result = await prepared.perform(isStillValid: { handoff.isValid }, handoff: handoff)
      XCTAssertEqual(result?.language, mode == 0 ? .korean : nil)
      XCTAssertEqual(handoff.commandCount, mode == 0 || mode == 3 ? 1 : 0)
      let expected: InputHandoffDiagnostics.Outcome =
        switch mode {
        case 0: .pending
        case 1: .budgetBeforeNative
        case 2: .nativeDispatchFailed
        case 3: .sourceUnacknowledged
        default: .contextCancelled
        }
      XCTAssertEqual(InputHandoffDiagnostics.snapshot.outcome, expected)
      if mode == 3 { XCTAssertEqual(InputHandoffDiagnostics.snapshot.stage, .nativeReleased) }
    }
  }

  @MainActor
  func testCancelledNativeRequestNeverDispatches() async throws {
    let handoff = TimedInputHandoff()
    let controller = InputSourceController(
      readSource: {
        InputSourceSnapshot(identifier: InputSourceController.abcIdentifier, language: .english)
      },
      selectSource: { _ in
        XCTFail("Unexpected TIS fallback")
        return false
      },
      prepareNativeSwitch: { NativeInputSourceSwitch() }, notifications: NotificationCenter(),
      acknowledgmentDelay: {})
    let prepared = try XCTUnwrap(controller.prepareSelection(language: .korean))
    let task = Task { await prepared.perform(isStillValid: { true }, handoff: handoff) }
    task.cancel()
    let result = await task.value
    XCTAssertNil(result)
    XCTAssertEqual(handoff.commandCount, 0)
    XCTAssertEqual(InputHandoffDiagnostics.snapshot.outcome, .contextCancelled)
  }

  func testUsesStableIdentifiersInsteadOfDisplayNames() {
    XCTAssertEqual(
      InputSourceController.language(forIdentifier: InputSourceController.abcIdentifier),
      .english
    )
    XCTAssertEqual(
      InputSourceController.language(forIdentifier: InputSourceController.korean2SetIdentifier),
      .korean
    )
    XCTAssertNil(InputSourceController.language(forIdentifier: "localized.display.name"))
    XCTAssertEqual(
      InputSourceController.identifier(for: .english), InputSourceController.abcIdentifier)
    XCTAssertEqual(
      InputSourceController.identifier(for: .korean),
      InputSourceController.korean2SetIdentifier
    )
  }
  @MainActor
  func testSelectionRequiresActualSourceReadback() {
    let old = InputSourceSnapshot(
      identifier: InputSourceController.abcIdentifier, language: .english)
    let controller = InputSourceController(readSource: { old }, selectSource: { _ in true })
    XCTAssertNil(controller.select(language: .korean))
  }

  @MainActor
  func testSelectionFailsWhenCurrentSourceIsUnavailable() {
    let controller = InputSourceController(readSource: { nil }, selectSource: { _ in true })
    XCTAssertNil(controller.select(language: .korean))
  }

  @MainActor
  func testSelectionReturnsVerifiedSourceOnly() {
    let actual = InputSourceSnapshot(
      identifier: InputSourceController.korean2SetIdentifier, language: .korean)
    let controller = InputSourceController(readSource: { actual }, selectSource: { _ in true })
    XCTAssertEqual(controller.select(language: .korean), actual)
    let failed = InputSourceController(readSource: { actual }, selectSource: { _ in false })
    XCTAssertNil(failed.select(language: .korean))
  }

  @MainActor
  func testConfirmationWaitsForNotificationAndDelayedReadbackBothDirections() async {
    for target in [TokenLanguage.korean, .english] {
      let center = NotificationCenter()
      var current = InputSourceSnapshot(
        identifier: InputSourceController.identifier(for: target.opposite),
        language: target.opposite)
      let desired = InputSourceSnapshot(
        identifier: InputSourceController.identifier(for: target), language: target)
      var requests = 0
      var delays = 0
      let controller = InputSourceController(
        readSource: { current },
        selectSource: { _ in
          requests += 1
          return true
        },
        notifications: center,
        acknowledgmentDelay: {
          delays += 1
          if delays == 1 { center.post(name: InputSourceController.sourceChanged, object: nil) }
          if delays == 2 { current = desired }
        })
      let result = await controller.selectAndConfirm(language: target, isStillValid: { true })
      XCTAssertEqual(result, desired)
      XCTAssertEqual(requests, 1)
      XCTAssertEqual(delays, 2)
    }
  }

  @MainActor
  func testReadbackAloneDoesNotReleaseSourceHandoff() async {
    let center = NotificationCenter()
    var current = InputSourceSnapshot(
      identifier: InputSourceController.abcIdentifier, language: .english)
    var requests = 0
    let controller = InputSourceController(
      readSource: { current },
      selectSource: { _ in
        requests += 1
        current = InputSourceSnapshot(
          identifier: InputSourceController.korean2SetIdentifier, language: .korean)
        return true
      }, notifications: center, acknowledgmentDelay: {})
    let result = await controller.selectAndConfirm(language: .korean, isStillValid: { true })
    XCTAssertNil(result)
    XCTAssertEqual(requests, 1)
  }

  @MainActor
  func testExpiredHandoffNeverRepeatsSourceRequest() async {
    let center = NotificationCenter()
    let current = InputSourceSnapshot(
      identifier: InputSourceController.abcIdentifier, language: .english)
    var valid = true
    var requests = 0
    let controller = InputSourceController(
      readSource: { current },
      selectSource: { _ in
        requests += 1
        return true
      },
      notifications: center, acknowledgmentDelay: { valid = false })
    let result = await controller.selectAndConfirm(language: .korean, isStillValid: { valid })
    XCTAssertNil(result)
    XCTAssertEqual(requests, 1)
  }

}
