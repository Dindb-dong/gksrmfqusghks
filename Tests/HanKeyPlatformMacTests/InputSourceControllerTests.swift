import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

final class InputSourceControllerTests: XCTestCase {
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
